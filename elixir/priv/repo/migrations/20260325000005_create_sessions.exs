# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :token_hash, :text, null: false
      add :expires_at, :utc_datetime, null: false
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:sessions, [:token_hash])
    create index(:sessions, [:account_id])
    create index(:sessions, [:expires_at])
  end
end
