# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateLists do
  use Ecto.Migration

  @moduledoc """
  Mastodon user lists. A list groups accounts the owner already
  follows; the list timeline filters their home timeline to just
  those authors.
  """

  def change do
    create table(:lists) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :title, :string, null: false
      # Mastodon list "exclusive": when true, members are removed from
      # the owner's main home timeline. Stored for parity even though
      # the home query doesn't consult it yet.
      add :replies_policy, :string, default: "list", null: false
      add :exclusive, :boolean, default: false, null: false

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: :updated_at)
    end

    create index(:lists, [:account_id])

    create table(:list_accounts, primary_key: false) do
      add :list_id, references(:lists, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
    end

    create unique_index(:list_accounts, [:list_id, :account_id])
    create index(:list_accounts, [:account_id])
  end
end
