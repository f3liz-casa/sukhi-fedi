# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateNoteCleanupLedger do
  use Ecto.Migration

  # Self-cleanup hard-deletes targeted notes (row + media cascade) and
  # federates the Delete. The ledger survives the deletion:
  #
  #   * `note_cleanup_ledger` — the "生成と削除のDB": one row per deleted note,
  #     keeping {account, note_id, the note's created_at, when it was deleted,
  #     why}. Append-only from the app's side. `note_id` is a plain bigint, not
  #     a FK with `on_delete`, because the ledger row must outlive the note row
  #     it records; it carries the creation/deletion timestamps itself.
  def change do
    create table(:note_cleanup_ledger) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :note_id, :bigint, null: false
      add :note_created_at, :utc_datetime, null: false
      add :deleted_at, :utc_datetime, null: false
      add :reason, :string
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create index(:note_cleanup_ledger, [:account_id])
    create unique_index(:note_cleanup_ledger, [:note_id])
  end
end
