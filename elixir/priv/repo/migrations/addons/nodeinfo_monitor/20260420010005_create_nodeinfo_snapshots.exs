# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateNodeinfoSnapshots do
  use Ecto.Migration

  def change do
    create table(:nodeinfo_snapshots) do
      add :monitored_instance_id,
          references(:monitored_instances, on_delete: :delete_all),
          null: false

      add :polled_at, :utc_datetime_usec, null: false
      add :version, :string
      add :software_name, :string
      add :raw, :map
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:nodeinfo_snapshots, [:monitored_instance_id, :polled_at])
  end
end
