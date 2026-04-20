# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateBoosts do
  use Ecto.Migration

  def change do
    create table(:boosts) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :note_id,    references(:notes,    on_delete: :delete_all), null: false
      add :ap_id,      :string
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:boosts, [:account_id, :note_id])
    create index(:boosts, [:note_id])
  end
end
