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

  alias SukhiFedi.{Repo, Snowflake}
  alias SukhiFedi.Lists
  alias SukhiFedi.Schema.{Account, Boost, Follow, Note, Tag}

  @default_limit 20
  @max_limit 40

  # A boost has no snowflake id of its own — it's a plain `bigserial` row — so
  # the home feed mints a cursor from the boost's `created_at` via
  # `SukhiFedi.Snowflake` (the same layout as a note id). That puts boosts and
  # notes in one time-sortable id space, which is what lets us interleave them
  # and keep id-based (`max_id`/`since_id`) pagination working across both.

  @doc """
  Home timeline: notes from accounts the viewer follows (state=accepted),
  plus the viewer's own notes, interleaved with boosts (reblogs) by those
  same accounts. Newest first. Mastodon pagination opts.

  Boosts come back as wrapper maps (`%{__boost__: true, ...}`) carrying the
  booster and the already-enriched boosted note; `MastodonStatus.render`
  turns each into a reblog Status. Notes come back as `%Note{}` as before.
  """
  @spec home(Account.t() | integer(), keyword() | map()) :: [Note.t() | map()]
  def home(%Account{id: id, username: username}, opts \\ []) do
    opts = normalize_opts(opts)
    limit = opts |> Map.get(:limit, @default_limit) |> clamp_limit()

    actor_uri = local_actor_uri(username)
    following_account_ids = following_local_account_ids(actor_uri)

    # Members of an *exclusive* circle are followed (so their posts arrive)
    # but kept out of home — you read them in the circle's own feed. One
    # exception: their *replies to a post on this server* (in_reply_to points
    # back here, ≈ to you) still surface, so a circle member talking to you is
    # never silently dropped from home. Boosts have no reply notion, so circle
    # members stay fully quiet there (boost_account_ids keeps the subtraction).
    excluded = Lists.excluded_account_ids(id)
    reply_here = "https://#{SukhiFedi.Config.domain!()}/%"

    note_account_ids = [id | following_account_ids]
    boost_account_ids = [id | following_account_ids -- excluded]

    notes =
      Note
      |> where([n], n.account_id in ^note_account_ids)
      |> where([n], n.account_id not in ^excluded or like(n.in_reply_to_ap_id, ^reply_here))
      |> where([n], n.visibility in ["public", "unlisted", "followers"])
      |> maybe_only_media(opts[:only_media])
      |> maybe_hide_sensitive(opts[:hide_sensitive])
      |> apply_paging(opts)
      |> Repo.all()
      |> Repo.preload([:account, :media, :tags])
      |> SukhiFedi.Notes.with_refs(id)

    # RT(ブースト)を隠すフィルタ。home だけがブーストを混ぜるので、ここで止める。
    boosts =
      if opts[:hide_boosts], do: [], else: home_boosts(boost_account_ids, opts, limit, id)

    # Both notes (id) and boost wrappers (synthesized id) share one
    # time-sortable id space, so a plain id-desc merge is chronological.
    (notes ++ boosts)
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.take(limit)
  end

  # Boosts by `account_ids`, wrapped for the reblog render. Only reblogs of
  # public/unlisted notes surface — a followers-only or direct note must not
  # leak into the home feed via someone else's boost. Paged in the same
  # id space as notes (see `@snowflake_epoch_ms`).
  defp home_boosts(account_ids, opts, limit, viewer_id) do
    rows =
      from(b in Boost,
        join: n in Note,
        on: n.id == b.note_id,
        join: ba in Account,
        on: ba.id == b.account_id,
        where: b.account_id in ^account_ids,
        where: n.visibility in ["public", "unlisted"],
        order_by: [desc: b.created_at],
        limit: ^limit,
        select: %{boost_id: b.id, created_at: b.created_at, booster: ba, note: n}
      )
      |> boost_time_bounds(opts)
      |> Repo.all()

    enriched =
      rows
      |> Enum.map(& &1.note)
      |> Repo.preload([:account, :media, :tags])
      |> SukhiFedi.Notes.with_refs(viewer_id)

    rows
    |> Enum.zip(enriched)
    |> Enum.map(fn {row, note} ->
      %{
        __boost__: true,
        id: boost_cursor(row.created_at, row.boost_id),
        boost_id: row.boost_id,
        created_at: row.created_at,
        account: row.booster,
        note: note
      }
    end)
    |> boost_exact_paging(opts)
  end

  # Mint a note-id-compatible cursor for a boost from its timestamp.
  defp boost_cursor(%DateTime{} = created_at, boost_id),
    do: Snowflake.encode(DateTime.to_unix(created_at, :millisecond), boost_id)

  # DB-side pre-filter: bound `created_at` by the millisecond a cursor encodes
  # (inclusive, since the 16-bit counter tail is resolved exactly in Elixir by
  # `boost_exact_paging`). Cheap and keeps the fetched set to one page.
  defp boost_time_bounds(query, opts) do
    query
    |> maybe_boost_upper(opts[:max_id])
    |> maybe_boost_lower(opts[:since_id] || opts[:min_id])
  end

  defp maybe_boost_upper(q, nil), do: q

  defp maybe_boost_upper(q, max_id) when is_integer(max_id),
    do: where(q, [b], b.created_at <= ^Snowflake.to_datetime(max_id))

  defp maybe_boost_lower(q, nil), do: q

  defp maybe_boost_lower(q, since_id) when is_integer(since_id),
    do: where(q, [b], b.created_at >= ^Snowflake.to_datetime(since_id))

  # Exact cursor comparison on the synthesized ids (the DB bound was inclusive).
  defp boost_exact_paging(wrappers, opts) do
    wrappers
    |> filter_cursor(opts[:max_id], fn id, c -> c < id end)
    |> filter_cursor(opts[:since_id] || opts[:min_id], fn id, c -> c > id end)
  end

  defp filter_cursor(wrappers, nil, _cmp), do: wrappers

  defp filter_cursor(wrappers, id, cmp) when is_integer(id),
    do: Enum.filter(wrappers, fn w -> cmp.(id, w.id) end)

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
    |> maybe_hide_sensitive(opts[:hide_sensitive])
    |> Repo.all()
    |> Repo.preload([:account, :media, :tags])
    |> SukhiFedi.Notes.with_refs()
  end

  # Local-origin notes carry no `ap_id` (it's synthesized on demand), so a
  # mirrored remote post always has one. Filtering on that is equivalent to
  # joining the author and checking `accounts.domain IS NULL`, but drops the
  # join. `SukhiFedi.Notes.local_notes/1` is the shared origin predicate.
  defp maybe_local_only(query, true), do: SukhiFedi.Notes.local_notes(query)

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
    |> maybe_only_media(opts[:only_media])
    |> maybe_hide_sensitive(opts[:hide_sensitive])
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

  # センシティブ / CW 付きを隠す。sensitive フラグと cw(spoiler)どちらも無い
  # ものだけ残す。
  defp maybe_hide_sensitive(q, true),
    do: where(q, [n], n.sensitive == false and is_nil(n.cw))

  defp maybe_hide_sensitive(q, _), do: q

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
