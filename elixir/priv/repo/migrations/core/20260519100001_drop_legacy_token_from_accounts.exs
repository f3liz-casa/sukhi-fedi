# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.DropLegacyTokenFromAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      remove :token, :text
    end
  end
end
