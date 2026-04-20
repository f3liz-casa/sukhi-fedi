# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.PinnedNotes do
  @moduledoc """
  Pinned-notes addon — featured collection for actor profiles
  (FEP-e232 / Mastodon featured collection).
  """

  use SukhiFedi.Addon, id: :pinned_notes

  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{PinnedNote, Account}

  def pin(account_id, note_id) do
    %PinnedNote{}
    |> PinnedNote.changeset(%{account_id: account_id, note_id: note_id})
    |> Repo.insert(on_conflict: :nothing)
  end

  def unpin(account_id, note_id) do
    from(p in PinnedNote,
      where: p.account_id == ^account_id and p.note_id == ^note_id
    )
    |> Repo.delete_all()

    :ok
  end

  def list_for_account(account_id) do
    from(p in PinnedNote,
      where: p.account_id == ^account_id,
      order_by: [asc: p.position, asc: p.created_at],
      preload: :note
    )
    |> Repo.all()
    |> Enum.map(& &1.note)
  end

  def list_for_username(username) do
    account = Repo.get_by(Account, username: username)
    if account, do: list_for_account(account.id), else: []
  end

  def featured_uri(actor_uri), do: "#{actor_uri}/featured"
end
