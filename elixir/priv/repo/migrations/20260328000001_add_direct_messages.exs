# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Repo.Migrations.AddDirectMessages do
  use Ecto.Migration

  def change do
    alter table(:notes) do
      add :in_reply_to_ap_id, :text
      add :conversation_ap_id, :text
    end

    create index(:notes, [:conversation_ap_id])
    create index(:notes, [:in_reply_to_ap_id])

    create table(:conversation_participants) do
      add :conversation_ap_id, :text, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :created_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:conversation_participants, [:conversation_ap_id, :account_id])
    create index(:conversation_participants, [:account_id])
  end
end
