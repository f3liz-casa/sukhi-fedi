# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddPinnedNotes do
  use Ecto.Migration

  def change do
    create table(:pinned_notes) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :note_id, references(:notes, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:pinned_notes, [:account_id, :note_id])
    create index(:pinned_notes, [:account_id, :position])
  end
end
