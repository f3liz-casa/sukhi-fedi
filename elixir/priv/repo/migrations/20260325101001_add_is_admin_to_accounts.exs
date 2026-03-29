# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddIsAdminToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :is_admin, :boolean, default: false, null: false
    end
  end
end
