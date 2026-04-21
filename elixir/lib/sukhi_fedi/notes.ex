# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Notes do
  alias SukhiFedi.{Repo, Outbox}
  alias SukhiFedi.Schema.Note

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
    |> case do
      {:ok, %{note: note}} -> {:ok, note}
      {:error, :note, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end
end
