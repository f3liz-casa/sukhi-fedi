# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Accounts do
  @moduledoc """
  Account context. Reachable from the api plugin node via
  `SukhiApi.GatewayRpc.call(SukhiFedi.Accounts, :fun, [args])`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SukhiFedi.{Outbox, Repo}
  alias SukhiFedi.Schema.{Account, Boost, Follow, Note, Session}

  # ── reads ─────────────────────────────────────────────────────────────────

  def get_account_by_username(username) do
    Repo.get_by(Account, username: username)
  end

  @doc """
  Fetch by id. Returns `{:ok, account}` or `{:error, :not_found}`.
  """
  @spec get_account(integer() | binary()) :: {:ok, Account.t()} | {:error, :not_found}
  def get_account(id) do
    id =
      cond do
        is_integer(id) -> id
        is_binary(id) ->
          case Integer.parse(id) do
            {n, ""} -> n
            _ -> nil
          end
        true -> nil
      end

    case id && Repo.get(Account, id) do
      nil -> {:error, :not_found}
      %Account{} = a -> {:ok, a}
    end
  end

  @doc """
  Resolve a Mastodon-style `acct:` lookup. Today this is local-only.
  Remote `user@host` returns `{:error, :not_found}` until WebFinger
  fan-out lands in a future PR.
  """
  @spec lookup_by_acct(String.t()) :: {:ok, Account.t()} | {:error, :not_found}
  def lookup_by_acct(acct) when is_binary(acct) do
    bare = String.trim_leading(acct, "@")

    case String.split(bare, "@", parts: 2) do
      [username] ->
        case get_account_by_username(username) do
          nil -> {:error, :not_found}
          a -> {:ok, a}
        end

      [username, host] ->
        local_domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")

        if host == local_domain do
          case get_account_by_username(username) do
            nil -> {:error, :not_found}
            a -> {:ok, a}
          end
        else
          {:error, :not_found}
        end
    end
  end

  @doc """
  Resolve a session cookie value to its bound `Account`. Returns the
  account, or `nil` if the token is unknown / expired.

  Used by the OAuth `/oauth/authorize` capability to confirm that the
  browser has an authenticated session before minting an authorization
  code on the user's behalf.
  """
  def get_account_by_session_token(token) when is_binary(token) and token != "" do
    h = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(Session, token_hash: h) do
      nil ->
        nil

      %Session{expires_at: exp} = s ->
        if DateTime.compare(exp, now) == :gt do
          Repo.get(Account, s.account_id)
        else
          nil
        end
    end
  end

  def get_account_by_session_token(_), do: nil

  # ── counts ───────────────────────────────────────────────────────────────

  @doc """
  Return the three Mastodon profile counters in a single roundtrip.

  The numbers don't need to be perfectly fresh on every profile view,
  so we cache for 60 s in an ETS table to absorb refresh storms when a
  user is featured/linked. Cache misses fall through to a single
  `SELECT count` per dimension. Acceptable at MVP scale; revisit when a
  Counters table or trigger-maintained aggregate becomes worth the
  complexity.
  """
  @spec counts_for(integer()) :: %{followers: integer(), following: integer(), statuses: integer()}
  def counts_for(account_id) when is_integer(account_id) do
    case cache_get({:counts, account_id}) do
      {:ok, value} ->
        value

      :miss ->
        actor_uri = local_actor_uri(account_id)

        followers =
          Repo.aggregate(
            from(f in Follow, where: f.followee_id == ^account_id and f.state == "accepted"),
            :count,
            :id
          )

        following =
          if actor_uri do
            Repo.aggregate(
              from(f in Follow, where: f.follower_uri == ^actor_uri and f.state == "accepted"),
              :count,
              :id
            )
          else
            0
          end

        statuses =
          Repo.aggregate(
            from(n in Note, where: n.account_id == ^account_id),
            :count,
            :id
          )

        result = %{followers: followers, following: following, statuses: statuses}
        cache_put({:counts, account_id}, result)
        result
    end
  end

  # ── update_credentials ───────────────────────────────────────────────────

  @doc """
  Update profile fields (display_name, summary/note, avatar/header,
  bot, locked is currently ignored — no `locked` column yet). Emits
  `sns.outbox.actor.updated` so federated peers can refresh their
  cached actor JSON.
  """
  @spec update_credentials(Account.t() | integer(), map()) ::
          {:ok, Account.t()} | {:error, :not_found | {:validation, map()}}
  def update_credentials(%Account{} = account, attrs) do
    do_update(account, attrs)
  end

  def update_credentials(account_id, attrs) when is_integer(account_id) do
    case Repo.get(Account, account_id) do
      nil -> {:error, :not_found}
      a -> do_update(a, attrs)
    end
  end

  defp do_update(%Account{} = account, attrs) do
    cs = Account.changeset_credentials(account, attrs)

    Multi.new()
    |> Multi.update(:account, cs)
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.actor.updated",
      "account",
      & &1.account.id,
      fn %{account: a} -> %{account_id: a.id, username: a.username} end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{account: a}} ->
        cache_invalidate({:counts, a.id})
        {:ok, a}

      {:error, :account, %Ecto.Changeset{} = cs, _} ->
        {:error, {:validation, changeset_errors(cs)}}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  # ── statuses by account ──────────────────────────────────────────────────

  @doc """
  List notes by an account, with Mastodon pagination opts and filters.

  Opts (all optional):
    * `:max_id`, `:since_id`, `:min_id`, `:limit`
    * `:exclude_replies` — drop notes with `in_reply_to_ap_id`
    * `:exclude_reblogs` — currently a no-op (notes table has no boost
      flag; boosts live in their own table and aren't surfaced here yet)
    * `:only_media` — keep only notes with at least one attached Media

  Returns the page as a list (newest first).
  """
  @spec list_statuses(integer(), keyword() | map()) :: [Note.t()]
  def list_statuses(account_id, opts \\ []) do
    opts = normalize_opts(opts)

    query =
      from(n in Note,
        where: n.account_id == ^account_id,
        order_by: [desc: n.id]
      )

    query =
      Enum.reduce(opts, query, fn
        {:max_id, v}, q when not is_nil(v) -> from(n in q, where: n.id < ^v)
        {:since_id, v}, q when not is_nil(v) -> from(n in q, where: n.id > ^v)
        {:min_id, v}, q when not is_nil(v) -> from(n in q, where: n.id > ^v)
        {:exclude_replies, true}, q -> from(n in q, where: is_nil(n.in_reply_to_ap_id))
        _, q -> q
      end)

    limit = Map.get(opts, :limit, 20)

    notes =
      query
      |> limit(^limit)
      |> Repo.all()
      |> Repo.preload([:account, :media])

    if Map.get(opts, :only_media, false) do
      Enum.filter(notes, fn n -> length(n.media || []) > 0 end)
    else
      notes
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  @counts_table :sukhi_fedi_account_counts
  @counts_ttl_ms 60_000

  defp cache_get(key) do
    ensure_table()

    case :ets.lookup(@counts_table, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at,
          do: {:ok, value},
          else: :miss

      [] ->
        :miss
    end
  end

  defp cache_put(key, value) do
    ensure_table()
    expires_at = System.monotonic_time(:millisecond) + @counts_ttl_ms
    :ets.insert(@counts_table, {key, value, expires_at})
    value
  end

  defp cache_invalidate(key) do
    ensure_table()
    :ets.delete(@counts_table, key)
  end

  defp ensure_table do
    case :ets.whereis(@counts_table) do
      :undefined ->
        :ets.new(@counts_table, [:set, :public, :named_table, read_concurrency: true])

      _ref ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp local_actor_uri(account_id) do
    case Repo.get(Account, account_id) do
      nil ->
        nil

      %Account{username: u} ->
        domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
        "https://#{domain}/users/#{u}"
    end
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts

  defp changeset_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, options} ->
      Enum.reduce(options, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end

  # Suppress "unused alias" — Boost will be referenced by a future PR
  # (favourite/reblog) but kept here so the alias matches the schema set.
  _ = Boost
end
