# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Notes.Counts do
  @moduledoc """
  Per-note numbers for the Status render: interaction counts, the
  Misskey-style reaction breakdown, and the viewer's own flags
  (favourited / reblogged / bookmarked / pinned) — single-note and
  bulk variants.
  """

  import Ecto.Query

  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{Bookmark, Boost, Note, PinnedNote, Reaction}

  # The same ⭐ `SukhiFedi.Notes.Interactions` stores favourites as —
  # resolved at compile time so the queries below pin a plain string.
  @favourite_emoji SukhiFedi.Notes.Interactions.favourite_emoji()

  @doc """
  Per-note interaction counts. Used by `MastodonStatus.render/2`.

  Returns `%{replies: int, reblogs: int, favourites: int}` for a
  single note in three cheap counts.
  """
  @spec counts_for_note(integer()) :: %{
          replies: integer(),
          reblogs: integer(),
          favourites: integer()
        }
  def counts_for_note(note_id) when is_integer(note_id) do
    note = Repo.get(Note, note_id)
    ap_id = note && note.ap_id

    replies =
      case ap_id do
        nil -> 0
        ap -> Repo.aggregate(from(n in Note, where: n.in_reply_to_ap_id == ^ap), :count, :id)
      end

    reblogs = Repo.aggregate(from(b in Boost, where: b.note_id == ^note_id), :count, :id)

    favourites =
      Repo.aggregate(
        from(r in Reaction, where: r.note_id == ^note_id and r.emoji == ^@favourite_emoji),
        :count,
        :id
      )

    %{replies: replies, reblogs: reblogs, favourites: favourites}
  end

  @doc """
  Bulk variant: counts for many notes in one DB roundtrip per
  dimension. Returns a map keyed by note_id.
  """
  @spec counts_for_notes([integer()]) ::
          %{integer() => %{replies: integer(), reblogs: integer(), favourites: integer()}}
  def counts_for_notes([]), do: %{}

  def counts_for_notes(note_ids) when is_list(note_ids) do
    ap_ids =
      from(n in Note, where: n.id in ^note_ids, select: {n.id, n.ap_id})
      |> Repo.all()

    id_to_ap = Map.new(ap_ids)

    reblogs_map =
      from(b in Boost,
        where: b.note_id in ^note_ids,
        group_by: b.note_id,
        select: {b.note_id, count(b.id)}
      )
      |> Repo.all()
      |> Map.new()

    fav_map =
      from(r in Reaction,
        where: r.note_id in ^note_ids and r.emoji == ^@favourite_emoji,
        group_by: r.note_id,
        select: {r.note_id, count(r.id)}
      )
      |> Repo.all()
      |> Map.new()

    ap_id_list = id_to_ap |> Map.values() |> Enum.reject(&is_nil/1)

    replies_by_ap =
      if ap_id_list == [] do
        %{}
      else
        from(n in Note,
          where: n.in_reply_to_ap_id in ^ap_id_list,
          group_by: n.in_reply_to_ap_id,
          select: {n.in_reply_to_ap_id, count(n.id)}
        )
        |> Repo.all()
        |> Map.new()
      end

    Map.new(note_ids, fn id ->
      ap = Map.get(id_to_ap, id)

      {id,
       %{
         replies: Map.get(replies_by_ap, ap, 0),
         reblogs: Map.get(reblogs_map, id, 0),
         favourites: Map.get(fav_map, id, 0)
       }}
    end)
  end

  @doc """
  Misskey-style reaction breakdown for many notes in one DB roundtrip.
  Returns `%{note_id => [%{name, count, me}]}`, ordered by count desc
  then emoji asc for deterministic UI.

  Excludes the favourite emoji — those still flow through
  `favourites_count`/`favourited` to stay Mastodon-compatible.
  """
  @spec reactions_for_notes([integer()], integer() | nil) :: %{
          integer() => [%{name: String.t(), count: non_neg_integer(), me: boolean()}]
        }
  def reactions_for_notes(note_ids, viewer_id \\ nil)
  def reactions_for_notes([], _viewer_id), do: %{}

  def reactions_for_notes(note_ids, viewer_id) when is_list(note_ids) do
    rows =
      from(r in Reaction,
        where: r.note_id in ^note_ids and r.emoji != ^@favourite_emoji,
        group_by: [r.note_id, r.emoji],
        select: {r.note_id, r.emoji, count(r.id)}
      )
      |> Repo.all()

    mine =
      case viewer_id do
        nil ->
          MapSet.new()

        id when is_integer(id) ->
          from(r in Reaction,
            where:
              r.note_id in ^note_ids and r.account_id == ^id and r.emoji != ^@favourite_emoji,
            select: {r.note_id, r.emoji}
          )
          |> Repo.all()
          |> MapSet.new()
      end

    emoji_keys = rows |> Enum.map(fn {_, e, _} -> e end) |> Enum.uniq()
    urls = SukhiFedi.CustomEmojis.lookup_many(emoji_keys)

    rows
    |> Enum.group_by(fn {note_id, _emoji, _count} -> note_id end)
    |> Map.new(fn {note_id, group} ->
      list =
        group
        |> Enum.map(fn {_note_id, emoji, count} ->
          icon = Map.get(urls, emoji, %{})

          %{
            name: emoji,
            count: count,
            me: MapSet.member?(mine, {note_id, emoji}),
            url: Map.get(icon, :url),
            static_url: Map.get(icon, :static_url) || Map.get(icon, :url)
          }
        end)
        |> Enum.sort_by(fn %{count: c, name: n} -> {-c, n} end)

      {note_id, list}
    end)
  end

  @doc """
  Per-note viewer-context flags: `%{favourited, reblogged, bookmarked, pinned}`.
  """
  @spec viewer_flags(integer() | nil, integer()) :: %{
          favourited: boolean(),
          reblogged: boolean(),
          bookmarked: boolean(),
          pinned: boolean()
        }
  def viewer_flags(nil, _note_id),
    do: %{favourited: false, reblogged: false, bookmarked: false, pinned: false}

  def viewer_flags(account_id, note_id) when is_integer(account_id) and is_integer(note_id) do
    %{
      favourited:
        Repo.exists?(
          from(r in Reaction,
            where:
              r.account_id == ^account_id and r.note_id == ^note_id and
                r.emoji == ^@favourite_emoji
          )
        ),
      reblogged:
        Repo.exists?(
          from(b in Boost, where: b.account_id == ^account_id and b.note_id == ^note_id)
        ),
      bookmarked:
        Repo.exists?(
          from(b in Bookmark, where: b.account_id == ^account_id and b.note_id == ^note_id)
        ),
      pinned:
        Repo.exists?(
          from(p in PinnedNote, where: p.account_id == ^account_id and p.note_id == ^note_id)
        )
    }
  end

  @doc "Bulk variant of `viewer_flags/2`. Returns map keyed by note_id."
  @spec viewer_flags_many(integer() | nil, [integer()]) :: %{
          integer() => %{
            favourited: boolean(),
            reblogged: boolean(),
            bookmarked: boolean(),
            pinned: boolean()
          }
        }
  def viewer_flags_many(_account_id, []), do: %{}

  def viewer_flags_many(nil, note_ids) do
    Map.new(note_ids, fn id ->
      {id, %{favourited: false, reblogged: false, bookmarked: false, pinned: false}}
    end)
  end

  def viewer_flags_many(account_id, note_ids) when is_integer(account_id) and is_list(note_ids) do
    fav =
      from(r in Reaction,
        where:
          r.account_id == ^account_id and r.note_id in ^note_ids and
            r.emoji == ^@favourite_emoji,
        select: r.note_id
      )
      |> Repo.all()
      |> MapSet.new()

    reblog =
      from(b in Boost,
        where: b.account_id == ^account_id and b.note_id in ^note_ids,
        select: b.note_id
      )
      |> Repo.all()
      |> MapSet.new()

    bm =
      from(b in Bookmark,
        where: b.account_id == ^account_id and b.note_id in ^note_ids,
        select: b.note_id
      )
      |> Repo.all()
      |> MapSet.new()

    pin =
      from(p in PinnedNote,
        where: p.account_id == ^account_id and p.note_id in ^note_ids,
        select: p.note_id
      )
      |> Repo.all()
      |> MapSet.new()

    Map.new(note_ids, fn id ->
      {id,
       %{
         favourited: MapSet.member?(fav, id),
         reblogged: MapSet.member?(reblog, id),
         bookmarked: MapSet.member?(bm, id),
         pinned: MapSet.member?(pin, id)
       }}
    end)
  end
end
