# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Repo.Migrations.CreateOauthConnections do
  use Ecto.Migration

  def change do
    create table(:oauth_connections) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :provider, :text, null: false
      add :provider_uid, :text, null: false
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:oauth_connections, [:provider, :provider_uid])
    create index(:oauth_connections, [:account_id])
  end
end
