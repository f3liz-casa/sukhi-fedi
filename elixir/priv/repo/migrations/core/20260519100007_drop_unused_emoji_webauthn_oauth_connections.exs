# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.DropUnusedEmojiWebauthnOauthConnections do
  use Ecto.Migration

  @moduledoc """
  Three more tables with no readers and no writers in production code:

    * `emojis`               — custom-emoji scaffold; nobody calls
      `Schema.Emoji` and no Mastodon view advertises it.
    * `webauthn_credentials` — placeholder for a passkey login flow
      that never landed; the schema has no changeset and no caller.
    * `oauth_connections`    — placeholder for third-party login
      (Sign in with Google et al.); same story.

  When any of these surfaces actually ships, the table comes back in
  the migration that introduces the feature, not as dead scaffolding.
  """

  def change do
    drop_if_exists table(:emojis)
    drop_if_exists table(:webauthn_credentials)
    drop_if_exists table(:oauth_connections)
  end
end
