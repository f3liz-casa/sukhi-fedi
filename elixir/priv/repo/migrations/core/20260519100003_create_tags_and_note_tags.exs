# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateTagsAndNoteTags do
  use Ecto.Migration

  @moduledoc """
  Hashtags. `tags.name` is lower-cased and stripped of the leading `#`
  at insert time so a search for `#Elixir` and `#elixir` collapses to
  one row. `note_tags` is a plain join table — no timestamps, the
  note's `created_at` is enough for ordering.
  """

  def change do
    # `name` is stored lower-cased without the leading `#` — the
    # caller normalises before insert. citext would let the DB enforce
    # this but it requires the extension; doing it in Elixir keeps the
    # migration portable.
    create table(:tags) do
      add :name, :text, null: false
      add :created_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:tags, [:name])

    create table(:note_tags, primary_key: false) do
      add :note_id, references(:notes, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
    end

    create unique_index(:note_tags, [:note_id, :tag_id])
    create index(:note_tags, [:tag_id, :note_id])
  end
end
