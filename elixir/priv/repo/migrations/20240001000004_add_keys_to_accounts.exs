# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddKeysToAccounts do
  use Ecto.Migration
  def change do
    alter table(:accounts) do
      add :private_key_jwk, :map
      add :public_key_jwk, :map
    end
  end
end
