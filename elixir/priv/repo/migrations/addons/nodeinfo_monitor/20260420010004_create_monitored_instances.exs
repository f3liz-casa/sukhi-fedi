# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateMonitoredInstances do
  use Ecto.Migration

  def change do
    create table(:monitored_instances) do
      add :domain, :string, null: false
      add :actor_id, references(:accounts, on_delete: :delete_all), null: false
      add :last_polled_at, :utc_datetime_usec
      add :last_version, :string
      add :software_name, :string
      add :consecutive_failures, :integer, null: false, default: 0
      add :inactive, :boolean, null: false, default: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:monitored_instances, [:domain])
    # PollCoordinator query: active instances ordered by last-polled-first.
    create index(:monitored_instances, [:inactive, :last_polled_at])
  end
end
