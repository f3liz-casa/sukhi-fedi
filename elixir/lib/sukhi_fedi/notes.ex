# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Notes do
  @moduledoc """
  Notes context. Reachable from the api plugin node via
  `SukhiApi.GatewayRpc.call(SukhiFedi.Notes, :fun, [args])`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SukhiFedi.{Outbox, Repo}
  alias SukhiFedi.Schema.{Account, Bookmark, Boost, Media, Note, PinnedNote, Reaction}

  @favourite_emoji "⭐"

  # ── create ───────────────────────────────────────────────────────────────

  @doc """
  Create a note and enqueue the `sns.outbox.note.created` event atomically.

  A single Ecto.Multi transaction does both the `notes` insert and the
  `outbox` row. Combined with `Outbox.Relay` this delivers
  "DB commit = event durable" semantics.
  """
  def create_note(attrs) do
    Multi.new()
    |> Multi.insert(:note, Note.changeset(%Note{}, attrs))
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.note.created",
      "note",
      & &1.note.id,
      fn %{note: note} ->
        %{
          note_id: note.id,
          account_id: note.account_id,
          visibility: note.visibility,
          content: note.content
        }
      end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{note: note}} -> {:ok, Repo.preload(note, [:account, :media])}
      {:error, :note, %Ecto.Changeset{} = cs, _} -> {:error, {:validation, changeset_errors(cs)}}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Create a status from Mastodon-shaped input.

  Translates:
    * `spoiler_text` → `cw`
    * `media_ids[]` → resolves Media rows owned by the same account,
      attaches via `note_media` join inside the same Multi
    * `in_reply_to_id` → looks up local Note's `ap_id` for `in_reply_to_ap_id`

  Same outbox + transactional guarantees as `create_note/1`.

  > TODO(pr5): direct visibility (DMs) is rejected here pending mention
  > extraction; only public/unlisted/followers ship in PR3.
  """
  @spec create_status(Account.t() | integer(), map()) ::
          {:ok, Note.t()} | {:error, atom() | {:validation, map()}}
  def create_status(%Account{id: aid}, params), do: create_status(aid, params)

  def create_status(account_id, params) when is_integer(account_id) do
    visibility = normalize_visibility(params[:visibility] || params["visibility"] || "public")

    if visibility == "direct" do
      {:error, :direct_visibility_not_supported}
    else
      attrs =
        %{
          account_id: account_id,
          content: params[:status] || params["status"] || "",
          cw: params[:spoiler_text] || params["spoiler_text"] || params[:cw] || params["cw"],
          visibility: visibility
        }
        |> resolve_in_reply_to(params)

      media_ids = list_media_ids(params)

      Multi.new()
      |> Multi.insert(:note, Note.changeset(%Note{}, attrs))
      |> attach_media(media_ids, account_id)
      |> Outbox.enqueue_multi(
        :outbox_event,
        "sns.outbox.note.created",
        "note",
        & &1.note.id,
        fn %{note: n} ->
          %{
            note_id: n.id,
            account_id: n.account_id,
            visibility: n.visibility,
            content: n.content,
            media_ids: media_ids
          }
        end
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{note: note}} ->
          {:ok, Repo.preload(note, [:account, :media])}

        {:error, :note, %Ecto.Changeset{} = cs, _} ->
          {:error, {:validation, changeset_errors(cs)}}

        {:error, :media_not_owned, _, _} ->
          {:error, :media_not_owned}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  defp resolve_in_reply_to(attrs, params) do
    case params[:in_reply_to_id] || params["in_reply_to_id"] do
      nil ->
        attrs

      id ->
        case parse_int(id) do
          nil ->
            attrs

          int_id ->
            case Repo.one(from n in Note, where: n.id == ^int_id, select: n.ap_id) do
              nil -> attrs
              ap_id -> Map.put(attrs, :in_reply_to_ap_id, ap_id)
            end
        end
    end
  end

  defp list_media_ids(params) do
    raw =
      params[:media_ids] || params["media_ids"] || params["media_ids[]"] || []

    raw
    |> List.wrap()
    |> Enum.map(&parse_int/1)
    |> Enum.reject(&is_nil/1)
  end

  defp attach_media(multi, [], _account_id), do: multi

  defp attach_media(multi, media_ids, account_id) do
    multi
    |> Multi.run(:media_check, fn repo, _changes ->
      owned =
        from(m in Media, where: m.id in ^media_ids and m.account_id == ^account_id, select: m.id)
        |> repo.all()

      if MapSet.equal?(MapSet.new(owned), MapSet.new(media_ids)) do
        {:ok, owned}
      else
        {:error, :not_owned}
      end
    end)
    |> Multi.run(:media_attached, fn repo, %{note: note, media_check: media_ids} ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        Enum.map(media_ids, fn mid ->
          %{note_id: note.id, media_id: mid, inserted_at: now, updated_at: now}
        end)

      {n, _} = repo.insert_all("note_media", rows)
      {:ok, n}
    end)
  end

  # ── reads ────────────────────────────────────────────────────────────────

  @doc """
  Load a single note by id with the assocs Mastodon Status JSON
  needs: account, media, poll, reactions.
  """
  @spec get_note(integer() | binary()) :: {:ok, Note.t()} | {:error, :not_found}
  def get_note(id) do
    case parse_int(id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get(Note, n) do
          nil -> {:error, :not_found}
          note -> {:ok, Repo.preload(note, [:account, :media, :poll, :reactions])}
        end
    end
  end

  # ── delete ───────────────────────────────────────────────────────────────

  @doc """
  Delete a note. Owner-checked: returns `{:error, :forbidden}` if the
  caller doesn't own the note.

  Emits `sns.outbox.note.deleted` carrying the AP id so federated
  peers can scrub their cached copies.
  """
  @spec delete_note(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found | :forbidden}
  def delete_note(%Account{id: aid}, note_id), do: delete_note(aid, note_id)

  def delete_note(account_id, note_id) when is_integer(account_id) do
    case parse_int(note_id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get(Note, n) do
          nil ->
            {:error, :not_found}

          %Note{account_id: ^account_id} = note ->
            do_delete(note)

          %Note{} ->
            {:error, :forbidden}
        end
    end
  end

  defp do_delete(%Note{} = note) do
    Multi.new()
    |> Multi.delete(:note, note)
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.note.deleted",
      "note",
      fn _ -> note.id end,
      fn _ ->
        %{note_id: note.id, ap_id: note.ap_id, account_id: note.account_id}
      end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{note: deleted}} -> {:ok, deleted}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  # ── context (ancestors / descendants) ────────────────────────────────────

  @max_depth 60

  @doc """
  Build a Mastodon Context for a note: ancestors (parents up the
  reply chain) and descendants (replies down the tree). Capped at
  depth #{@max_depth} like Mastodon.

  Implementation: recursive CTEs over `notes.in_reply_to_ap_id` ↔
  `notes.ap_id`. Locally-known nodes only — remote ancestors require
  fetching, which is deferred.
  """
  @spec context(integer() | binary()) ::
          {:ok, %{ancestors: [Note.t()], descendants: [Note.t()]}} | {:error, :not_found}
  def context(note_id) do
    case parse_int(note_id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get(Note, n) do
          nil -> {:error, :not_found}
          note -> {:ok, %{ancestors: ancestors_of(note), descendants: descendants_of(note)}}
        end
    end
  end

  defp ancestors_of(%Note{in_reply_to_ap_id: nil}), do: []

  defp ancestors_of(%Note{in_reply_to_ap_id: parent_ap_id}) do
    walk_ancestors(parent_ap_id, [], 0)
  end

  defp walk_ancestors(_ap_id, acc, depth) when depth >= @max_depth, do: Enum.reverse(acc)

  defp walk_ancestors(nil, acc, _depth), do: Enum.reverse(acc)

  defp walk_ancestors(ap_id, acc, depth) do
    case Repo.one(from n in Note, where: n.ap_id == ^ap_id, preload: [:account, :media]) do
      nil -> Enum.reverse(acc)
      note -> walk_ancestors(note.in_reply_to_ap_id, [note | acc], depth + 1)
    end
  end

  defp descendants_of(%Note{ap_id: nil}), do: []
  defp descendants_of(%Note{ap_id: ap_id}), do: walk_descendants([ap_id], [], 0)

  defp walk_descendants(_frontier, acc, depth) when depth >= @max_depth, do: Enum.reverse(acc)
  defp walk_descendants([], acc, _depth), do: Enum.reverse(acc)

  defp walk_descendants(frontier, acc, depth) do
    children =
      from(n in Note,
        where: n.in_reply_to_ap_id in ^frontier,
        order_by: [asc: n.id],
        preload: [:account, :media]
      )
      |> Repo.all()

    case children do
      [] ->
        Enum.reverse(acc)

      _ ->
        next_frontier = Enum.map(children, & &1.ap_id) |> Enum.reject(&is_nil/1)
        walk_descendants(next_frontier, Enum.reverse(children, acc), depth + 1)
    end
  end

  # ── interactions: favourite / reblog / bookmark / pin ────────────────────

  @doc """
  Mark a note as favourited by `account`. Idempotent — second call is
  a no-op. Emits `sns.outbox.like.created` on first insert (delivery
  node will translate to `Like` AP activity).
  """
  @spec favourite(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def favourite(%Account{id: aid}, note_id), do: favourite(aid, note_id)

  def favourite(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      case Repo.get_by(Reaction, account_id: account_id, note_id: note.id, emoji: @favourite_emoji) do
        %Reaction{} ->
          {:ok, note}

        nil ->
          Multi.new()
          |> Multi.insert(
            :reaction,
            Reaction.changeset(%Reaction{}, %{
              account_id: account_id,
              note_id: note.id,
              emoji: @favourite_emoji
            })
          )
          |> Outbox.enqueue_multi(
            :outbox_event,
            "sns.outbox.like.created",
            "reaction",
            & &1.reaction.id,
            fn %{reaction: r} ->
              %{
                reaction_id: r.id,
                account_id: r.account_id,
                note_id: r.note_id,
                note_ap_id: note.ap_id,
                emoji: r.emoji
              }
            end
          )
          |> Repo.transaction()
          |> case do
            {:ok, _} -> {:ok, note}
            {:error, _step, reason, _} -> {:error, reason}
          end
      end
    end)
  end

  @doc "Remove favourite. Idempotent. Emits `sns.outbox.like.undone` on actual delete."
  @spec unfavourite(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def unfavourite(%Account{id: aid}, note_id), do: unfavourite(aid, note_id)

  def unfavourite(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      case Repo.get_by(Reaction, account_id: account_id, note_id: note.id, emoji: @favourite_emoji) do
        nil ->
          {:ok, note}

        %Reaction{} = r ->
          Multi.new()
          |> Multi.delete(:reaction, r)
          |> Outbox.enqueue_multi(
            :outbox_event,
            "sns.outbox.like.undone",
            "reaction",
            fn _ -> r.id end,
            fn _ ->
              %{reaction_id: r.id, account_id: r.account_id, note_id: r.note_id, note_ap_id: note.ap_id}
            end
          )
          |> Repo.transaction()
          |> case do
            {:ok, _} -> {:ok, note}
            {:error, _step, reason, _} -> {:error, reason}
          end
      end
    end)
  end

  @doc "Reblog (Mastodon) / Boost (internal). Idempotent. Emits `sns.outbox.announce.created`."
  @spec reblog(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def reblog(%Account{id: aid}, note_id), do: reblog(aid, note_id)

  def reblog(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      case Repo.get_by(Boost, account_id: account_id, note_id: note.id) do
        %Boost{} ->
          {:ok, note}

        nil ->
          Multi.new()
          |> Multi.insert(
            :boost,
            Boost.changeset(%Boost{}, %{account_id: account_id, note_id: note.id})
          )
          |> Outbox.enqueue_multi(
            :outbox_event,
            "sns.outbox.announce.created",
            "boost",
            & &1.boost.id,
            fn %{boost: b} ->
              %{
                boost_id: b.id,
                account_id: b.account_id,
                note_id: b.note_id,
                note_ap_id: note.ap_id
              }
            end
          )
          |> Repo.transaction()
          |> case do
            {:ok, _} -> {:ok, note}
            {:error, _step, reason, _} -> {:error, reason}
          end
      end
    end)
  end

  @doc "Undo reblog. Idempotent. Emits `sns.outbox.announce.undone` on actual delete."
  @spec unreblog(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def unreblog(%Account{id: aid}, note_id), do: unreblog(aid, note_id)

  def unreblog(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      case Repo.get_by(Boost, account_id: account_id, note_id: note.id) do
        nil ->
          {:ok, note}

        %Boost{} = b ->
          Multi.new()
          |> Multi.delete(:boost, b)
          |> Outbox.enqueue_multi(
            :outbox_event,
            "sns.outbox.announce.undone",
            "boost",
            fn _ -> b.id end,
            fn _ ->
              %{boost_id: b.id, account_id: b.account_id, note_id: b.note_id, note_ap_id: note.ap_id}
            end
          )
          |> Repo.transaction()
          |> case do
            {:ok, _} -> {:ok, note}
            {:error, _step, reason, _} -> {:error, reason}
          end
      end
    end)
  end

  @doc "Bookmark a note. Local-only — no outbox event. Idempotent."
  @spec bookmark(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def bookmark(%Account{id: aid}, note_id), do: bookmark(aid, note_id)

  def bookmark(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      _ =
        %Bookmark{account_id: account_id, note_id: note.id}
        |> Repo.insert(on_conflict: :nothing)

      {:ok, note}
    end)
  end

  @spec unbookmark(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found}
  def unbookmark(%Account{id: aid}, note_id), do: unbookmark(aid, note_id)

  def unbookmark(account_id, note_id) when is_integer(account_id) do
    with_loaded_note(note_id, fn note ->
      _ =
        Repo.delete_all(
          from b in Bookmark, where: b.account_id == ^account_id and b.note_id == ^note.id
        )

      {:ok, note}
    end)
  end

  @doc """
  Pin a note to the actor's featured collection. Owner-checked (you
  can only pin your own notes). Emits `sns.outbox.add.created` so
  remote followers can update their featured collection cache.
  """
  @spec pin(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found | :forbidden}
  def pin(%Account{id: aid}, note_id), do: pin(aid, note_id)

  def pin(account_id, note_id) when is_integer(account_id) do
    case load_owned_note(account_id, note_id) do
      {:error, e} ->
        {:error, e}

      {:ok, note} ->
        case Repo.get_by(PinnedNote, account_id: account_id, note_id: note.id) do
          %PinnedNote{} ->
            {:ok, note}

          nil ->
            Multi.new()
            |> Multi.insert(
              :pinned,
              PinnedNote.changeset(%PinnedNote{}, %{account_id: account_id, note_id: note.id})
            )
            |> Outbox.enqueue_multi(
              :outbox_event,
              "sns.outbox.add.created",
              "pinned_note",
              & &1.pinned.id,
              fn %{pinned: p} ->
                %{
                  pinned_id: p.id,
                  account_id: p.account_id,
                  note_id: p.note_id,
                  note_ap_id: note.ap_id
                }
              end
            )
            |> Repo.transaction()
            |> case do
              {:ok, _} -> {:ok, note}
              {:error, _step, reason, _} -> {:error, reason}
            end
        end
    end
  end

  @spec unpin(Account.t() | integer(), integer() | binary()) ::
          {:ok, Note.t()} | {:error, :not_found | :forbidden}
  def unpin(%Account{id: aid}, note_id), do: unpin(aid, note_id)

  def unpin(account_id, note_id) when is_integer(account_id) do
    case load_owned_note(account_id, note_id) do
      {:error, e} ->
        {:error, e}

      {:ok, note} ->
        case Repo.get_by(PinnedNote, account_id: account_id, note_id: note.id) do
          nil ->
            {:ok, note}

          %PinnedNote{} = p ->
            Multi.new()
            |> Multi.delete(:pinned, p)
            |> Outbox.enqueue_multi(
              :outbox_event,
              "sns.outbox.remove.created",
              "pinned_note",
              fn _ -> p.id end,
              fn _ ->
                %{pinned_id: p.id, account_id: p.account_id, note_id: p.note_id, note_ap_id: note.ap_id}
              end
            )
            |> Repo.transaction()
            |> case do
              {:ok, _} -> {:ok, note}
              {:error, _step, reason, _} -> {:error, reason}
            end
        end
    end
  end

  # ── counts + viewer flags ────────────────────────────────────────────────

  @doc """
  Per-note interaction counts. Used by `MastodonStatus.render/2`.

  Returns `%{replies: int, reblogs: int, favourites: int}` for a
  single note in three cheap counts.
  """
  @spec counts_for_note(integer()) :: %{replies: integer(), reblogs: integer(), favourites: integer()}
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
          from r in Reaction,
            where: r.account_id == ^account_id and r.note_id == ^note_id and r.emoji == ^@favourite_emoji
        ),
      reblogged:
        Repo.exists?(from b in Boost, where: b.account_id == ^account_id and b.note_id == ^note_id),
      bookmarked:
        Repo.exists?(from b in Bookmark, where: b.account_id == ^account_id and b.note_id == ^note_id),
      pinned:
        Repo.exists?(
          from p in PinnedNote, where: p.account_id == ^account_id and p.note_id == ^note_id
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

  @doc """
  List the viewer's bookmarked notes (newest bookmark first, Mastodon
  pagination opts).
  """
  @spec list_bookmarks(Account.t() | integer(), keyword() | map()) :: [Note.t()]
  def list_bookmarks(%Account{id: aid}, opts), do: list_bookmarks(aid, opts)

  def list_bookmarks(account_id, opts) when is_integer(account_id) do
    opts = normalize_kv(opts)
    limit = clamp_limit(Map.get(opts, :limit, 20))

    from(b in Bookmark,
      join: n in Note,
      on: b.note_id == n.id,
      where: b.account_id == ^account_id,
      order_by: [desc: b.id],
      limit: ^limit,
      select: n
    )
    |> Repo.all()
    |> Repo.preload([:account, :media])
  end

  @doc "Same as list_bookmarks but for favourites (Reactions with the favourite emoji)."
  @spec list_favourites(Account.t() | integer(), keyword() | map()) :: [Note.t()]
  def list_favourites(%Account{id: aid}, opts), do: list_favourites(aid, opts)

  def list_favourites(account_id, opts) when is_integer(account_id) do
    opts = normalize_kv(opts)
    limit = clamp_limit(Map.get(opts, :limit, 20))

    from(r in Reaction,
      join: n in Note,
      on: r.note_id == n.id,
      where: r.account_id == ^account_id and r.emoji == ^@favourite_emoji,
      order_by: [desc: r.id],
      limit: ^limit,
      select: n
    )
    |> Repo.all()
    |> Repo.preload([:account, :media])
  end

  defp with_loaded_note(note_id, fun) do
    case parse_int(note_id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get(Note, n) do
          nil -> {:error, :not_found}
          note -> fun.(note)
        end
    end
  end

  defp load_owned_note(account_id, note_id) do
    case parse_int(note_id) do
      nil ->
        {:error, :not_found}

      n ->
        case Repo.get(Note, n) do
          nil -> {:error, :not_found}
          %Note{account_id: ^account_id} = note -> {:ok, note}
          %Note{} -> {:error, :forbidden}
        end
    end
  end

  defp normalize_kv(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_kv(opts) when is_map(opts), do: opts

  defp clamp_limit(n) when is_integer(n) and n > 0 and n <= 40, do: n
  defp clamp_limit(_), do: 20

  # ── helpers ──────────────────────────────────────────────────────────────

  defp normalize_visibility(v) when v in ["public", "unlisted", "followers", "direct"], do: v
  # Mastodon's "private" maps to our "followers"
  defp normalize_visibility("private"), do: "followers"
  defp normalize_visibility(_), do: "public"

  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp changeset_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
