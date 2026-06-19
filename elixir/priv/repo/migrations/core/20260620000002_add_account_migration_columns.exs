# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddAccountMigrationColumns do
  use Ecto.Migration

  # Account migration (Mastodon-standard Move + alsoKnownAs).
  #
  #   * `aliases` — the AP `alsoKnownAs` set: the other identities a person
  #     declares as "also me". For a local row it's the prior identities the
  #     user has added (so a Move *to* us verifies — the new actor lists the
  #     old one). For a remote row it mirrors the upstream actor's
  #     `alsoKnownAs`, which is what the inbound Move handler checks for
  #     bidirectional consent.
  #   * `moved_to_uri` — the AP `movedTo`: set on the *old* identity once it
  #     has moved, so every screen renders the truthful "moved to @new"
  #     state. NULL means "not moved". For remote rows this mirrors upstream.
  def change do
    alter table(:accounts) do
      add :aliases, {:array, :text}, null: false, default: []
      add :moved_to_uri, :text
    end
  end
end
