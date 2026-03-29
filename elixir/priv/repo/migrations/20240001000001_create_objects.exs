# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateObjects do
  use Ecto.Migration

  def change do
    create table(:objects) do
      add :ap_id, :text, null: false
      add :type, :text, null: false
      add :actor_id, :text, null: false
      add :raw_json, :map, null: false
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:objects, [:ap_id])
    create index(:objects, [:actor_id])
    create index(:objects, [:created_at])
  end
end
