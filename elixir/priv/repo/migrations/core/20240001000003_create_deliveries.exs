# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateDeliveries do
  use Ecto.Migration

  def change do
    create table(:deliveries) do
      add :object_id, references(:objects), null: false
      add :inbox_url, :text, null: false
      add :state, :text, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :next_retry, :utc_datetime
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end
  end
end
