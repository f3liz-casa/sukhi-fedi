# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateOauthAccessTokens do
  use Ecto.Migration

  def change do
    create table(:oauth_access_tokens) do
      add :token_hash, :text, null: false
      add :refresh_token_hash, :text
      add :app_id, references(:oauth_apps, on_delete: :delete_all), null: false
      # NULL on client_credentials grants (no end-user identity).
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :scopes, :text, null: false
      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:oauth_access_tokens, [:token_hash])

    create unique_index(:oauth_access_tokens, [:refresh_token_hash],
             where: "refresh_token_hash IS NOT NULL"
           )

    create index(:oauth_access_tokens, [:account_id])
    create index(:oauth_access_tokens, [:app_id])
  end
end
