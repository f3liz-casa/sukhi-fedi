# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.PinnedNotes do
  @moduledoc """
  Manages pinned (featured) notes for actor profiles (FEP-e232 / Mastodon featured collection).
  """

  import Ecto.Query
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.{PinnedNote, Note, Account}

  @doc "Pin a note for an account. Idempotent."
  def pin(account_id, note_id) do
    %PinnedNote{}
    |> PinnedNote.changeset(%{account_id: account_id, note_id: note_id})
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc "Unpin a note for an account."
  def unpin(account_id, note_id) do
    from(p in PinnedNote,
      where: p.account_id == ^account_id and p.note_id == ^note_id
    )
    |> Repo.delete_all()

    :ok
  end

  @doc "List pinned notes for an account, ordered by position."
  def list_for_account(account_id) do
    from(p in PinnedNote,
      where: p.account_id == ^account_id,
      order_by: [asc: p.position, asc: p.created_at],
      preload: :note
    )
    |> Repo.all()
    |> Enum.map(& &1.note)
  end

  @doc "List pinned notes for a username."
  def list_for_username(username) do
    account = Repo.get_by(Account, username: username)
    if account, do: list_for_account(account.id), else: []
  end

  @doc "Build the featured collection AP ID for an actor URI."
  def featured_uri(actor_uri), do: "#{actor_uri}/featured"
end
