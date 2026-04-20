# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Notes do
  import Ecto.Query
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
      {:error, :note, changeset, _} -> {:error, changeset}
      {:error, _step, reason, _} -> {:error, reason}
    end
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
end
