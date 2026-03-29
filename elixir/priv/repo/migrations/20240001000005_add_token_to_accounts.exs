# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddTokenToAccounts do
  use Ecto.Migration
  def change do
    alter table(:accounts) do
      add :token, :text
    end
    create unique_index(:accounts, [:token])
  end
end
