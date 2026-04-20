# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddPriority4Tables do
  use Ecto.Migration

  def change do
    # Media attachments
    create table(:media) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :url, :string, null: false
      add :remote_url, :string
      add :type, :string, null: false  # image, video, audio, unknown
      add :blurhash, :string
      add :description, :text
      add :width, :integer
      add :height, :integer
      add :size, :integer
      add :tags, {:array, :string}, default: []
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end
    create index(:media, [:account_id])

    # Note-Media join table
    create table(:note_media) do
      add :note_id, references(:notes, on_delete: :delete_all), null: false
      add :media_id, references(:media, on_delete: :delete_all), null: false
    end
    create unique_index(:note_media, [:note_id, :media_id])

    # Custom emojis
    create table(:emojis) do
      add :shortcode, :string, null: false
      add :url, :string, null: false
      add :category, :string
      add :aliases, {:array, :string}, default: []
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end
    create unique_index(:emojis, [:shortcode])

    # Reactions (Misskey-style)
    create table(:reactions) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :note_id, references(:notes, on_delete: :delete_all), null: false
      add :emoji, :string, null: false  # :shortcode: or unicode
      add :ap_id, :string
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end
    create unique_index(:reactions, [:account_id, :note_id, :emoji])
    create index(:reactions, [:note_id])

    # Polls
    create table(:polls) do
      add :note_id, references(:notes, on_delete: :delete_all), null: false
      add :expires_at, :utc_datetime
      add :multiple, :boolean, default: false
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end
    create unique_index(:polls, [:note_id])

    # Poll options
    create table(:poll_options) do
      add :poll_id, references(:polls, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :position, :integer, null: false
    end
    create index(:poll_options, [:poll_id])

    # Poll votes
    create table(:poll_votes) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :poll_id, references(:polls, on_delete: :delete_all), null: false
      add :option_id, references(:poll_options, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end
    create unique_index(:poll_votes, [:account_id, :poll_id, :option_id])
    create index(:poll_votes, [:poll_id])

    # Add MFM and CW to notes
    alter table(:notes) do
      add :cw, :string  # Content warning
      add :mfm, :text   # Raw MFM syntax
    end
  end
end
