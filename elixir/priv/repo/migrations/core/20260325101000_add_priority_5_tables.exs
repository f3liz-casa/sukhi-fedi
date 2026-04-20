# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddPriority5Tables do
  use Ecto.Migration

  def change do
    # Mutes
    create table(:mutes) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :target_id, references(:accounts, on_delete: :delete_all), null: false
      add :expires_at, :utc_datetime
      timestamps()
    end
    create unique_index(:mutes, [:account_id, :target_id])
    create index(:mutes, [:account_id])

    # Blocks
    create table(:blocks) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :target_id, references(:accounts, on_delete: :delete_all), null: false
      timestamps()
    end
    create unique_index(:blocks, [:account_id, :target_id])
    create index(:blocks, [:account_id])

    # Reports
    create table(:reports) do
      add :account_id, references(:accounts, on_delete: :nilify_all)
      add :target_id, references(:accounts, on_delete: :delete_all), null: false
      add :note_id, references(:notes, on_delete: :nilify_all)
      add :comment, :text
      add :status, :string, default: "open"
      add :resolved_at, :utc_datetime
      add :resolved_by_id, references(:accounts, on_delete: :nilify_all)
      timestamps()
    end
    create index(:reports, [:status])
    create index(:reports, [:target_id])

    # Instance blocks (defederation)
    create table(:instance_blocks) do
      add :domain, :string, null: false
      add :severity, :string, default: "suspend"
      add :reason, :text
      add :created_by_id, references(:accounts, on_delete: :nilify_all)
      timestamps()
    end
    create unique_index(:instance_blocks, [:domain])

    # Account suspensions
    alter table(:accounts) do
      add :suspended_at, :utc_datetime
      add :suspended_by_id, references(:accounts, on_delete: :nilify_all)
      add :suspension_reason, :text
    end
    create index(:accounts, [:suspended_at])

    # Bookmarks
    create table(:bookmarks) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :note_id, references(:notes, on_delete: :delete_all), null: false
      timestamps()
    end
    create unique_index(:bookmarks, [:account_id, :note_id])
    create index(:bookmarks, [:account_id, :inserted_at])

    # Web Push subscriptions
    create table(:push_subscriptions) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh_key, :text, null: false
      add :auth_key, :text, null: false
      add :alerts, :map, default: %{}
      timestamps()
    end
    create unique_index(:push_subscriptions, [:endpoint])
    create index(:push_subscriptions, [:account_id])

    # Articles (long-form content)
    create table(:articles) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :ap_id, :string, null: false
      add :title, :string, null: false
      add :content, :text, null: false
      add :summary, :text
      add :published_at, :utc_datetime
      add :updated_at_ap, :utc_datetime
      timestamps()
    end
    create unique_index(:articles, [:ap_id])
    create index(:articles, [:account_id, :inserted_at])
  end
end
