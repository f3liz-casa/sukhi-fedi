# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddAttachedAtToMedia do
  use Ecto.Migration

  def change do
    alter table(:media) do
      # Set when the Media row is first attached to a Note via note_media.
      # Used by `update_media/3` to refuse mutation post-attachment
      # (Mastodon contract: PUT /api/v1/media/:id only works pre-attach).
      add :attached_at, :utc_datetime
    end

    create index(:media, [:attached_at], where: "attached_at IS NULL")
  end
end
