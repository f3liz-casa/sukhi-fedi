# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateRelays do
  use Ecto.Migration

  def change do
    create table(:relays) do
      add :actor_uri, :text, null: false
      add :inbox_uri, :text, null: false
      add :state, :text, null: false, default: "pending"
      add :created_by_id, references(:accounts, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:relays, [:actor_uri])
    create index(:relays, [:state])
  end
end
