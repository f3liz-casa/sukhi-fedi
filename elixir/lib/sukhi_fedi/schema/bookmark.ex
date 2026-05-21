# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Bookmark do
  use Ecto.Schema

  # Private per-account note save: local-only, never federated, idempotent.
  # Backs Mastodon bookmarks and Misskey favourites (`/i/favorites`) alike —
  # the storage carries no protocol-specific meaning, only the view layer does.
  schema "bookmarks" do
    belongs_to :account, SukhiFedi.Schema.Account
    belongs_to :note, SukhiFedi.Schema.Note
    timestamps()
  end
end
