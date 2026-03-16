# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Repo.Migrations.AddKeysToAccounts do
  use Ecto.Migration
  def change do
    alter table(:accounts) do
      add :private_key_jwk, :map
      add :public_key_jwk, :map
    end
  end
end
