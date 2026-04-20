# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Nats.Notes do
  @moduledoc """
  `db.note.*`, `db.bookmark.*`, `db.dm.*` topic handlers.
  """

  import SukhiFedi.Nats.Helpers
  import Ecto.Query

  alias SukhiFedi.{Notes, Repo, Schema, AP}
  alias SukhiFedi.Addons.{Bookmarks, PinnedNotes}
  alias SukhiFedi.Schema.ConversationParticipant

  # ── Notes ──────────────────────────────────────────────────────────────────

  def handle("db.note.create", %{"account_id" => account_id} = params) do
    attrs = %{
      "account_id" => account_id,
      "content" => params["text"],
      "visibility" => params["visibility"] || "public",
      "cw" => params["cw"],
      "mfm" => params["mfm"],
      "in_reply_to_ap_id" => params["in_reply_to_ap_id"],
      "conversation_ap_id" => params["conversation_ap_id"],
      "quote_of_ap_id" => params["quote_of_ap_id"]
    }

    case Notes.create_note(attrs) do
      {:ok, note} -> ok_resp(serialize_note(note))
      {:error, changeset} -> error_resp("Failed to create note: #{inspect(changeset.errors)}")
    end
  end

  def handle("db.note.get", %{"id" => id}) do
    case Notes.get_note(id) do
      nil -> error_resp("Note not found")
      note -> ok_resp(serialize_note(note))
    end
  end

  def handle("db.note.delete", %{"id" => id, "account_id" => account_id}) do
    case Notes.get_note(id) do
      nil ->
        error_resp("Note not found")

      note ->
        if note.account_id == account_id do
          case Notes.delete_note(note) do
            {:ok, _} -> ok_resp(%{success: true})
            _ -> error_resp("Failed to delete note")
          end
        else
          error_resp("Forbidden")
        end
    end
  end

  def handle("db.note.like", %{"account_id" => account_id, "note_id" => note_id}) do
    case Notes.create_like(account_id, note_id) do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to like note")
    end
  end

  def handle("db.note.unlike", %{"account_id" => account_id, "note_id" => note_id}) do
    case Notes.delete_like(account_id, note_id) do
      :ok -> ok_resp(%{success: true})
      _ -> error_resp("Failed to unlike note")
    end
  end

  def handle("db.note.pin", %{"account_id" => account_id, "note_id" => note_id}) do
    case PinnedNotes.pin(account_id, note_id) do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to pin note")
    end
  end

  def handle("db.note.unpin", %{"account_id" => account_id, "note_id" => note_id}) do
    PinnedNotes.unpin(account_id, note_id)
    ok_resp(%{success: true})
  end

  # ── Reactions ──────────────────────────────────────────────────────────────

  def handle("db.note.reaction.add", %{"account_id" => account_id, "note_id" => note_id, "emoji" => emoji}) do
    with note when not is_nil(note) <- Repo.get(Schema.Note, note_id),
         {:ok, reaction} <-
           %Schema.Reaction{}
           |> Schema.Reaction.changeset(%{
             account_id: account_id,
             note_id: note_id,
             emoji: emoji
           })
           |> Repo.insert() do
      # Legacy Misskey extension subject; not in FedifyClient scope. Stays
      # on the old `ap.*` subscribe path for now.
      AP.Client.request("reaction.create", %{
        actor_id: account_id,
        note_id: note_id,
        emoji: emoji
      })

      ok_resp(%{
        id: reaction.id,
        emoji: reaction.emoji,
        account_id: reaction.account_id,
        note_id: reaction.note_id
      })
    else
      nil -> error_resp("Note not found")
      {:error, _} -> error_resp("Failed to add reaction")
    end
  end

  def handle("db.note.reaction.remove", %{"account_id" => account_id, "note_id" => note_id, "emoji" => emoji}) do
    reaction =
      Schema.Reaction
      |> where(
        [r],
        r.account_id == ^account_id and r.note_id == ^note_id and r.emoji == ^emoji
      )
      |> Repo.one()

    if reaction do
      Repo.delete(reaction)
      ok_resp(%{success: true})
    else
      error_resp("Reaction not found")
    end
  end

  def handle("db.note.reaction.list", %{"note_id" => note_id}) do
    reactions =
      Schema.Reaction
      |> where([r], r.note_id == ^note_id)
      |> Repo.all()

    ok_resp(%{
      reactions:
        Enum.map(reactions, fn r ->
          %{
            id: r.id,
            emoji: r.emoji,
            account_id: r.account_id,
            note_id: r.note_id
          }
        end)
    })
  end

  # ── Polls ──────────────────────────────────────────────────────────────────

  def handle("db.note.poll.vote", %{"account_id" => account_id, "note_id" => note_id, "choices" => choices}) do
    note = Repo.get(Schema.Note, note_id) |> Repo.preload(poll: :options)

    cond do
      is_nil(note) or is_nil(note.poll) ->
        error_resp("Poll not found")

      not (is_list(choices) and
             Enum.all?(choices, fn c -> c >= 0 and c <= length(note.poll.options) - 1 end)) ->
        error_resp("Invalid choices")

      true ->
        poll = note.poll

        existing =
          Schema.PollVote
          |> where([v], v.account_id == ^account_id and v.poll_id == ^poll.id)
          |> Repo.all()

        if length(existing) > 0 and not poll.multiple do
          error_resp("Already voted")
        else
          Enum.each(choices, fn idx ->
            option = Enum.at(poll.options, idx)

            %Schema.PollVote{}
            |> Schema.PollVote.changeset(%{
              account_id: account_id,
              poll_id: poll.id,
              option_id: option.id
            })
            |> Repo.insert()
          end)

          ok_resp(%{success: true})
        end
    end
  end

  # ── Bookmarks ──────────────────────────────────────────────────────────────

  def handle("db.bookmark.list", %{"account_id" => account_id} = params) do
    opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
    ok_resp(Bookmarks.list(account_id, opts))
  end

  def handle("db.bookmark.create", %{"account_id" => account_id, "note_id" => note_id}) do
    case Bookmarks.create(account_id, note_id) do
      {:ok, _} -> ok_resp(%{success: true})
      _ -> error_resp("Failed to create bookmark")
    end
  end

  def handle("db.bookmark.delete", %{"account_id" => account_id, "note_id" => note_id}) do
    Bookmarks.delete(account_id, note_id)
    ok_resp(%{success: true})
  end

  # ── Direct Messages / Conversations ────────────────────────────────────────

  def handle("db.dm.create", %{"account_id" => account_id} = params) do
    domain = Application.get_env(:sukhi_fedi, :domain, "localhost:4000")

    conversation_ap_id =
      params["conversation_ap_id"] ||
        "https://#{domain}/conversations/#{:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)}"

    attrs = %{
      "account_id" => account_id,
      "content" => params["text"] || params["content"],
      "visibility" => "direct",
      "cw" => params["cw"],
      "in_reply_to_ap_id" => params["in_reply_to_ap_id"],
      "conversation_ap_id" => conversation_ap_id
    }

    case Notes.create_note(attrs) do
      {:ok, note} ->
        %ConversationParticipant{}
        |> ConversationParticipant.changeset(%{
          conversation_ap_id: conversation_ap_id,
          account_id: account_id
        })
        |> Repo.insert(on_conflict: :nothing)

        Enum.each(params["recipient_ids"] || [], fn rid ->
          %ConversationParticipant{}
          |> ConversationParticipant.changeset(%{
            conversation_ap_id: conversation_ap_id,
            account_id: rid
          })
          |> Repo.insert(on_conflict: :nothing)
        end)

        ok_resp(Map.put(serialize_note(note), :conversation_ap_id, conversation_ap_id))

      {:error, changeset} ->
        error_resp("Failed to create DM: #{inspect(changeset.errors)}")
    end
  end

  def handle("db.dm.list", %{"account_id" => account_id} = params) do
    limit = parse_int(params["limit"], 20)

    conversations =
      from(cp in ConversationParticipant,
        where: cp.account_id == ^account_id,
        order_by: [desc: cp.created_at],
        limit: ^limit,
        select: cp.conversation_ap_id
      )
      |> Repo.all()

    ok_resp(%{conversations: conversations})
  end

  def handle("db.dm.conversation.get", %{"account_id" => account_id, "conversation_ap_id" => conv_id} = params) do
    is_participant =
      Repo.exists?(
        from(cp in ConversationParticipant,
          where: cp.account_id == ^account_id and cp.conversation_ap_id == ^conv_id
        )
      )

    if is_participant do
      limit = parse_int(params["limit"], 20)

      notes =
        from(n in Schema.Note,
          where: n.conversation_ap_id == ^conv_id,
          order_by: [asc: n.created_at],
          limit: ^limit
        )
        |> Repo.all()

      ok_resp(%{notes: Enum.map(notes, &serialize_note/1)})
    else
      error_resp("Forbidden")
    end
  end

  def handle(_, _), do: :unhandled
end
