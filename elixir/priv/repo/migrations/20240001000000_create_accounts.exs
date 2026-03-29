# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :username, :text, null: false
      add :display_name, :text
      add :summary, :text
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:accounts, [:username])
  end
end
