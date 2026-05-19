# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Lists do
  @moduledoc """
  Mastodon lists context.

  Lists are private to the owner: every read / write is scoped to a
  `viewer` account id. Membership is restricted to accounts the owner
  already follows in `accepted` state — the Mastodon spec is "any
  account you follow," and enforcing it here keeps the list-timeline
  query honest.

  All write helpers return either `{:ok, ...}` or `{:error, :not_found
  | :not_following}`. `:not_found` covers both "no such list" and
  "list belongs to someone else" so we don't leak existence.
  """

  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Follow, List, Note}

  # ── lists CRUD ──────────────────────────────────────────────────────────

  @spec list_for(integer()) :: [List.t()]
  def list_for(viewer_id) when is_integer(viewer_id) do
    Repo.all(from l in List, where: l.account_id == ^viewer_id, order_by: [asc: l.id])
  end

  @spec get(integer(), integer() | String.t()) :: {:ok, List.t()} | {:error, :not_found}
  def get(viewer_id, id) do
    case parse_id(id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get_by(List, id: n, account_id: viewer_id) do
          nil -> {:error, :not_found}
          %List{} = l -> {:ok, l}
        end
    end
  end

  @spec create(integer(), map()) :: {:ok, List.t()} | {:error, Ecto.Changeset.t()}
  def create(viewer_id, attrs) when is_integer(viewer_id) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("account_id", viewer_id)

    %List{}
    |> List.changeset(attrs)
    |> Repo.insert()
  end

  @spec update(integer(), integer() | String.t(), map()) ::
          {:ok, List.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update(viewer_id, id, attrs) do
    with {:ok, list} <- get(viewer_id, id) do
      list
      |> List.changeset(stringify(attrs))
      |> Repo.update()
    end
  end

  @spec delete(integer(), integer() | String.t()) ::
          {:ok, List.t()} | {:error, :not_found}
  def delete(viewer_id, id) do
    with {:ok, list} <- get(viewer_id, id) do
      Repo.delete(list)
    end
  end

  # ── membership ──────────────────────────────────────────────────────────

  @spec list_accounts(integer(), integer() | String.t()) ::
          {:ok, [map()]} | {:error, :not_found}
  def list_accounts(viewer_id, id) do
    with {:ok, %List{id: lid}} <- get(viewer_id, id) do
      rows =
        Repo.all(
          from la in "list_accounts",
            join: a in SukhiFedi.Schema.Account,
            on: a.id == la.account_id,
            where: la.list_id == ^lid,
            select: %{
              id: a.id,
              username: a.username,
              display_name: a.display_name,
              summary: a.summary,
              domain: a.domain,
              actor_uri: a.actor_uri,
              avatar_url: a.avatar_url,
              banner_url: a.banner_url
            }
        )

      {:ok, rows}
    end
  end

  @doc """
  Add members. Silently skips ids the viewer doesn't follow (we
  *don't* return `:not_following` for partials — Mastodon clients
  re-list immediately after).
  """
  @spec add_accounts(integer(), integer() | String.t(), [integer() | String.t()]) ::
          :ok | {:error, :not_found}
  def add_accounts(viewer_id, id, account_ids) do
    with {:ok, %List{id: lid}} <- get(viewer_id, id) do
      ids = Enum.map(account_ids, &parse_id/1) |> Enum.reject(&is_nil/1)
      viewer_uri = viewer_actor_uri(viewer_id)
      followed = followed_ids(viewer_uri, ids)

      rows = Enum.map(followed, fn aid -> %{list_id: lid, account_id: aid} end)

      Repo.insert_all("list_accounts", rows,
        on_conflict: :nothing,
        conflict_target: [:list_id, :account_id]
      )

      :ok
    end
  end

  @spec remove_accounts(integer(), integer() | String.t(), [integer() | String.t()]) ::
          :ok | {:error, :not_found}
  def remove_accounts(viewer_id, id, account_ids) do
    with {:ok, %List{id: lid}} <- get(viewer_id, id) do
      ids = Enum.map(account_ids, &parse_id/1) |> Enum.reject(&is_nil/1)

      Repo.delete_all(
        from la in "list_accounts",
          where: la.list_id == ^lid and la.account_id in ^ids
      )

      :ok
    end
  end

  # ── timeline ────────────────────────────────────────────────────────────

  @doc """
  List timeline: newest-first notes from list members (public,
  unlisted, followers). Same paging shape as the home timeline.
  """
  @spec timeline(integer(), integer() | String.t(), keyword() | map()) ::
          {:ok, [Note.t()]} | {:error, :not_found}
  def timeline(viewer_id, id, opts \\ []) do
    with {:ok, %List{id: lid}} <- get(viewer_id, id) do
      opts = if is_map(opts), do: opts, else: Map.new(opts)
      limit = clamp(opts[:limit])

      base =
        from n in Note,
          join: la in "list_accounts",
          on: la.account_id == n.account_id,
          where: la.list_id == ^lid and n.visibility in ["public", "unlisted", "followers"]

      results =
        base
        |> maybe_max_id(opts[:max_id])
        |> maybe_since_id(opts[:since_id])
        |> maybe_min_id(opts[:min_id])
        |> order_by([n], desc: n.id)
        |> limit(^limit)
        |> Repo.all()
        |> Repo.preload([:account, :media, :tags])

      {:ok, results}
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp followed_ids(_viewer_uri, []), do: []

  defp followed_ids(viewer_uri, ids) do
    Repo.all(
      from f in Follow,
        where:
          f.follower_uri == ^viewer_uri and f.followee_id in ^ids and f.state == "accepted",
        select: f.followee_id
    )
  end

  defp viewer_actor_uri(viewer_id) when is_integer(viewer_id) do
    case Repo.get(SukhiFedi.Schema.Account, viewer_id) do
      nil ->
        nil

      %SukhiFedi.Schema.Account{username: u} ->
        domain = SukhiFedi.Config.domain!()
        "https://#{domain}/users/#{u}"
    end
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  defp clamp(n) when is_integer(n) and n > 0 and n <= 40, do: n
  defp clamp(_), do: 20

  defp maybe_max_id(q, nil), do: q
  defp maybe_max_id(q, v), do: where(q, [n], n.id < ^to_int(v))

  defp maybe_since_id(q, nil), do: q
  defp maybe_since_id(q, v), do: where(q, [n], n.id > ^to_int(v))

  defp maybe_min_id(q, nil), do: q
  defp maybe_min_id(q, v), do: where(q, [n], n.id > ^to_int(v))

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
