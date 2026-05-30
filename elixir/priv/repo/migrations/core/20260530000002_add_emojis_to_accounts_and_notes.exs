# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddEmojisToAccountsAndNotes do
  use Ecto.Migration

  # Custom emoji used in a remote actor's name/bio or a note's content,
  # captured from the AP `tag` Emoji entries and surfaced as the Mastodon
  # `emojis` array so `:shortcode:` renders as an image.
  def change do
    alter table(:accounts) do
      add :emojis, {:array, :map}, null: false, default: []
    end

    alter table(:notes) do
      add :emojis, {:array, :map}, null: false, default: []
    end
  end
end
