# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Repo.Migrations.AddIsAdminToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :is_admin, :boolean, default: false, null: false
    end
  end
end
