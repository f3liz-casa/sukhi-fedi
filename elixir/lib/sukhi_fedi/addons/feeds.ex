# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.Feeds do
  @moduledoc """
  Feeds addon — home / local / public timeline queries.

  Reads moderation tables (Block, Mute, InstanceBlock) for filtering,
  so `:moderation` is a hard dependency.
  """

  use SukhiFedi.Addon, id: :feeds

  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Object, Follow, Block, Mute, InstanceBlock}

  @impl true
  def depends_on, do: [:moderation]

  @doc "Home feed (notes from accounts the user follows, plus their own)."
  def home_feed(account_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    max_id = Keyword.get(opts, :max_id)

    following_uris = get_following_uris(account_id)
    local_uri = "https://#{domain()}/users/#{get_username(account_id)}"
    blocked_uris = get_blocked_uris(account_id)
    muted_uris = get_muted_uris(account_id)
    blocked_domains = get_blocked_domains()

    query =
      from o in Object,
        where: o.type in ["Note", "Create"],
        where: o.actor_id in ^[local_uri | following_uris],
        where: o.actor_id not in ^blocked_uris,
        where: o.actor_id not in ^muted_uris,
        order_by: [desc: o.created_at],
        limit: ^limit

    query
    |> filter_blocked_domains(blocked_domains)
    |> maybe_max_id(max_id)
    |> Repo.all()
  end

  @doc "Local feed (notes authored by accounts on this instance)."
  def local_feed(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    max_id = Keyword.get(opts, :max_id)
    account_id = Keyword.get(opts, :account_id)

    blocked_uris = if account_id, do: get_blocked_uris(account_id), else: []
    muted_uris = if account_id, do: get_muted_uris(account_id), else: []

    query =
      from o in Object,
        where: o.type in ["Note", "Create"],
        where: fragment("? LIKE ?", o.actor_id, ^"https://#{domain()}%"),
        order_by: [desc: o.created_at],
        limit: ^limit

    query
    |> maybe_exclude(blocked_uris)
    |> maybe_exclude(muted_uris)
    |> maybe_max_id(max_id)
    |> Repo.all()
  end

  defp maybe_exclude(query, []), do: query

  defp maybe_exclude(query, uris) do
    from o in query, where: o.actor_id not in ^uris
  end

  defp maybe_max_id(query, nil), do: query

  defp maybe_max_id(query, max_id) do
    from o in query, where: o.id < ^max_id
  end

  defp get_following_uris(account_id) do
    from(f in Follow,
      where: f.followee_id == ^account_id and f.state == "accepted",
      select: f.follower_uri
    )
    |> Repo.all()
  end

  defp get_blocked_uris(account_id) do
    from(b in Block,
      join: a in assoc(b, :target),
      where: b.account_id == ^account_id,
      select: fragment("'https://' || ? || '/users/' || ?", ^domain(), a.username)
    )
    |> Repo.all()
  end

  defp get_muted_uris(account_id) do
    now = DateTime.utc_now()

    from(m in Mute,
      join: a in assoc(m, :target),
      where: m.account_id == ^account_id,
      where: is_nil(m.expires_at) or m.expires_at > ^now,
      select: fragment("'https://' || ? || '/users/' || ?", ^domain(), a.username)
    )
    |> Repo.all()
  end

  defp get_blocked_domains do
    Repo.all(from i in InstanceBlock, select: i.domain)
  end

  defp filter_blocked_domains(query, []), do: query

  defp filter_blocked_domains(query, domains) do
    Enum.reduce(domains, query, fn d, q ->
      from o in q, where: not fragment("? LIKE ?", o.actor_id, ^"%#{d}%")
    end)
  end

  defp get_username(account_id) do
    Repo.get!(SukhiFedi.Schema.Account, account_id).username
  end

  defp domain, do: Application.get_env(:sukhi_fedi, :domain, "localhost:4000")
end
