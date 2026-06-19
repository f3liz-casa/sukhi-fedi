# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateAccountNotes do
  use Ecto.Migration

  # A private, local-only label one account keeps about another — the
  # author's own memo (`POST /api/v1/accounts/:id/note`). It is never
  # federated and never shown to anyone but the author; it rides
  # alongside the target's real display name, it does not replace it.
  # Keyed by the (author, target) pair, so each author has at most one
  # note per target.
  def change do
    create table(:account_notes) do
      add :author_account_id, references(:accounts, on_delete: :delete_all), null: false
      add :target_account_id, references(:accounts, on_delete: :delete_all), null: false
      add :comment, :text, null: false, default: ""
      timestamps()
    end

    create unique_index(:account_notes, [:author_account_id, :target_account_id])
  end
end
