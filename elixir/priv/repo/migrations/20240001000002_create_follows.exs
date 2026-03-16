# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Repo.Migrations.CreateFollows do
  use Ecto.Migration

  def change do
    create table(:follows) do
      add :follower_uri, :text, null: false
      add :followee_id, references(:accounts), null: false
      add :state, :text, null: false, default: "pending"
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:follows, [:follower_uri, :followee_id])
  end
end
