# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Timelines do
  @moduledoc """
  Timeline queries for the Mastodon REST surface.

  Returns `Note` rows directly (not `Object` raw_json rows) so the api
  side can render Status JSON via `MastodonStatus.render/1` without
  parsing JSON-LD.

  The `:feeds` addon's Object-based queries are kept for the legacy
  `objects` table aggregation but are not used here. Once inbound AP
  Create(Note) writes a `notes` row in addition to `objects`, both
  paths can converge.
  """

  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Account, Follow, Note, Tag}

  @default_limit 20
  @max_limit 40

  @doc """
  Home timeline: notes from accounts the viewer follows (state=accepted),
  plus the viewer's own notes. Newest first. Mastodon pagination opts.
  """
  @spec home(Account.t() | integer(), keyword() | map()) :: [Note.t()]
  def home(%Account{id: id, username: username}, opts \\ []) do
    opts = normalize_opts(opts)

    actor_uri = local_actor_uri(username)
    following_account_ids = following_local_account_ids(actor_uri)

    visible_account_ids = [id | following_account_ids]

    Note
    |> where([n], n.account_id in ^visible_account_ids)
    |> where([n], n.visibility in ["public", "unlisted", "followers"])
    |> apply_paging(opts)
    |> Repo.all()
    |> Repo.preload([:account, :media, :tags])
    |> SukhiFedi.Notes.with_refs()
  end

  @doc """
  Public timeline: every public-visibility note authored by a local
  account. Remote posts (`accounts.domain IS NOT NULL`) are excluded
  by default; pass `local: false` to include them once the federated
  TL is exposed.

  Opts: `:max_id`, `:since_id`, `:min_id`, `:limit`, `:local`
  (default `true`), `:only_media`.
  """
  @spec public(keyword() | map()) :: [Note.t()]
  def public(opts \\ []) do
    opts = normalize_opts(opts)
    local? = Map.get(opts, :local, true)

    from(n in Note, where: n.visibility == "public")
    |> maybe_local_only(local?)
    |> apply_paging(opts)
    |> maybe_only_media(opts[:only_media])
    |> Repo.all()
    |> Repo.preload([:account, :media, :tags])
    |> SukhiFedi.Notes.with_refs()
  end

  defp maybe_local_only(query, true) do
    from(n in query,
      join: a in Account,
      on: a.id == n.account_id,
      where: is_nil(a.domain)
    )
  end

  defp maybe_local_only(query, _), do: query

  @doc """
  Hashtag timeline: public notes tagged with `hashtag` (lower-cased,
  no leading `#`).

  Opts: `:max_id`, `:since_id`, `:min_id`, `:limit`, `:local` (default true).
  """
  @spec tag(String.t(), keyword() | map()) :: [Note.t()]
  def tag(hashtag, opts \\ []) when is_binary(hashtag) do
    opts = normalize_opts(opts)
    local? = Map.get(opts, :local, true)
    name = hashtag |> String.trim_leading("#") |> String.downcase()

    base =
      from(n in Note,
        join: nt in "note_tags",
        on: nt.note_id == n.id,
        join: t in Tag,
        on: t.id == nt.tag_id,
        where: t.name == ^name and n.visibility == "public"
      )

    base
    |> maybe_local_only(local?)
    |> apply_paging(opts)
    |> Repo.all()
    |> Repo.preload([:account, :media, :tags])
    |> SukhiFedi.Notes.with_refs()
  end

  # ── paging ───────────────────────────────────────────────────────────────

  defp apply_paging(query, opts) do
    limit =
      opts
      |> Map.get(:limit, @default_limit)
      |> clamp_limit()

    query
    |> maybe_max_id(opts[:max_id])
    |> maybe_since_id(opts[:since_id])
    |> maybe_min_id(opts[:min_id])
    |> order_by([n], desc: n.id)
    |> limit(^limit)
  end

  defp maybe_max_id(q, nil), do: q
  defp maybe_max_id(q, v) when is_integer(v), do: where(q, [n], n.id < ^v)

  defp maybe_since_id(q, nil), do: q
  defp maybe_since_id(q, v) when is_integer(v), do: where(q, [n], n.id > ^v)

  defp maybe_min_id(q, nil), do: q
  defp maybe_min_id(q, v) when is_integer(v), do: where(q, [n], n.id > ^v)

  defp maybe_only_media(q, true),
    do: where(q, [n], fragment("EXISTS (SELECT 1 FROM note_media nm WHERE nm.note_id = ?)", n.id))

  defp maybe_only_media(q, _), do: q

  defp clamp_limit(n) when is_integer(n) and n > 0 and n <= @max_limit, do: n
  defp clamp_limit(_), do: @default_limit

  # ── helpers ──────────────────────────────────────────────────────────────

  defp following_local_account_ids(actor_uri) do
    from(f in Follow,
      join: a in Account,
      on: a.id == f.followee_id,
      where: f.follower_uri == ^actor_uri and f.state == "accepted",
      select: a.id
    )
    |> Repo.all()
  end

  defp local_actor_uri(username) do
    domain = SukhiFedi.Config.domain!()
    "https://#{domain}/users/#{username}"
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
end
