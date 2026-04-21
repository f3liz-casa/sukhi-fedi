# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateOauthApps do
  use Ecto.Migration

  def change do
    create table(:oauth_apps) do
      add :client_id, :text, null: false
      add :client_secret_hash, :text, null: false
      add :name, :text, null: false
      add :redirect_uri, :text, null: false
      add :scopes, :text, null: false, default: "read"
      add :website, :text
      add :owner_account_id, references(:accounts, on_delete: :nilify_all)
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:oauth_apps, [:client_id])
    create index(:oauth_apps, [:owner_account_id])
  end
end
