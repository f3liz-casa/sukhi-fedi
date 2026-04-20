# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Notes do
  import Ecto.Query
  alias SukhiFedi.{Repo, Outbox}
  alias SukhiFedi.Schema.{Note, Boost, Reaction}

  @favourite_emoji "⭐"

  @doc """
  Create a note and enqueue the `sns.outbox.note.created` event atomically.

  A single Ecto.Multi transaction does both the `notes` insert and the
  `outbox` row. Combined with `Outbox.Relay` this delivers
  "DB commit = event durable" semantics.
  """
  def create_note(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:note, Note.changeset(%Note{}, attrs))
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
    |> handle_result(:note)
  end

  @doc """
  Mastodon-style favourite. Stored as a `Reaction` row with the
  `#{@favourite_emoji}` emoji so the existing reactions UI surfaces
  it. Emits `sns.outbox.like.created` in the same transaction.
  """
  def create_like(account_id, note_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :reaction,
      Reaction.changeset(%Reaction{}, %{
        account_id: account_id,
        note_id: note_id,
        emoji: @favourite_emoji
      })
    )
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.like.created",
      "like",
      fn %{reaction: r} -> "#{r.account_id}->#{r.note_id}" end,
      fn %{reaction: r} ->
        %{account_id: r.account_id, note_id: r.note_id, emoji: r.emoji}
      end
    )
    |> Repo.transaction()
    |> handle_result(:reaction)
  end

  @doc """
  Undo a Mastodon-style favourite. Deletes the matching reaction row
  and emits `sns.outbox.like.undone`.
  """
  def delete_like(account_id, note_id) do
    case Repo.one(
           from r in Reaction,
             where:
               r.account_id == ^account_id and r.note_id == ^note_id and
                 r.emoji == ^@favourite_emoji
         ) do
      nil ->
        :ok

      %Reaction{} = reaction ->
        Ecto.Multi.new()
        |> Ecto.Multi.delete(:reaction, reaction)
        |> Outbox.enqueue_multi(
          :outbox_event,
          "sns.outbox.like.undone",
          "like",
          fn _ -> "#{account_id}->#{note_id}" end,
          fn _ -> %{account_id: account_id, note_id: note_id} end
        )
        |> Repo.transaction()
        |> case do
          {:ok, _} -> :ok
          {:error, _step, reason, _} -> {:error, reason}
        end
    end
  end

  @doc """
  Boost (Misskey renote / ActivityPub Announce) of an existing note.
  Inserts a `Boost` row and emits `sns.outbox.announce.created`. Returns
  the original (boosted) note so the controller's `serialize_note`
  surfaces it as the response body — Mastodon-style.
  """
  def create_boost(account_id, note_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:original_note, fn repo, _ ->
      case repo.get(Note, note_id) do
        nil -> {:error, :not_found}
        note -> {:ok, note}
      end
    end)
    |> Ecto.Multi.insert(
      :boost,
      Boost.changeset(%Boost{}, %{account_id: account_id, note_id: note_id})
    )
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.announce.created",
      "boost",
      & &1.boost.id,
      fn %{boost: b} ->
        %{boost_id: b.id, account_id: b.account_id, note_id: b.note_id}
      end
    )
    |> Repo.transaction()
    |> handle_result(:original_note)
  end

  @doc """
  Hard-delete a note and emit `sns.outbox.note.deleted` so federation
  can downstream-build a `Tombstone` / `Delete` activity from the
  payload.
  """
  def delete_note(%Note{} = note) do
    Ecto.Multi.new()
    |> Ecto.Multi.delete(:note, note)
    |> Outbox.enqueue_multi(
      :outbox_event,
      "sns.outbox.note.deleted",
      "note",
      fn _ -> note.id end,
      fn _ -> %{note_id: note.id, account_id: note.account_id, ap_id: note.ap_id} end
    )
    |> Repo.transaction()
    |> handle_result(:note)
  end

  def get_note(id) do
    Repo.get(Note, id)
  end

  def list_notes_by_account(account_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    
    from(n in Note,
      where: n.account_id == ^account_id,
      order_by: [desc: n.created_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def list_public_notes(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    from(n in Note,
      where: n.visibility == "public",
      order_by: [desc: n.created_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp handle_result({:ok, changes}, key), do: {:ok, Map.fetch!(changes, key)}
  defp handle_result({:error, key, %Ecto.Changeset{} = cs, _}, key), do: {:error, cs}
  defp handle_result({:error, _step, reason, _}, _key), do: {:error, reason}
end
