# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateOauthAuthorizationCodes do
  use Ecto.Migration

  def change do
    create table(:oauth_authorization_codes) do
      add :code_hash, :text, null: false
      add :app_id, references(:oauth_apps, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :redirect_uri, :text, null: false
      add :scopes, :text, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:oauth_authorization_codes, [:code_hash])
    create index(:oauth_authorization_codes, [:app_id])
    create index(:oauth_authorization_codes, [:expires_at])
  end
end
