# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Repo.Migrations.CreateNotes do
  use Ecto.Migration

  def change do
    create table(:notes) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :content, :text, null: false
      add :visibility, :text, null: false, default: "public"
      add :ap_id, :text
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create index(:notes, [:account_id])
    create index(:notes, [:created_at])
    create unique_index(:notes, [:ap_id])
  end
end
