# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Repo.Migrations.AddTokenToAccounts do
  use Ecto.Migration
  def change do
    alter table(:accounts) do
      add :token, :text
    end
    create unique_index(:accounts, [:token])
  end
end
