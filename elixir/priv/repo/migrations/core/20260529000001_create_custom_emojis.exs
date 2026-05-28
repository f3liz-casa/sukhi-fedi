# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateCustomEmojis do
  use Ecto.Migration

  @moduledoc """
  Custom emoji directory. Used today by Misskey-style EmojiReact: when
  a remote actor reacts with `:blobcat:` + a `tag` Emoji entry, we
  upsert a row here and store the namespaced shortcode
  (`:blobcat@misskey.io:`) as the reaction emoji so identical
  shortcodes from different origins don't collide.

  Also lays the groundwork for inline `:shortcode:` in note content
  (Mastodon `/api/v1/custom_emojis`), even though that's a separate
  rollout.

  `domain IS NULL` ⇔ local emoji. `(shortcode, domain)` is unique so
  upserts on inbound activity are idempotent.
  """

  def change do
    create table(:custom_emojis) do
      add :shortcode, :string, null: false
      add :domain, :string
      add :image_url, :string, null: false
      add :static_url, :string
      add :visible_in_picker, :boolean, null: false, default: true
      add :last_fetched_at, :utc_datetime
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:custom_emojis, [:shortcode, :domain])
  end
end
