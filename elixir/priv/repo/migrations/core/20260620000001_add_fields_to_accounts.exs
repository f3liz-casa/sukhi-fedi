# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddFieldsToAccounts do
  use Ecto.Migration

  # Profile fields: a few static key/value rows a person chooses to show
  # on their own profile (Mastodon `fields` / AP `attachment` PropertyValue).
  # They federate the same on every screen — local, remote, every client —
  # so what a viewer sees is what the person actually wrote. For remote
  # rows this mirrors the upstream actor's `attachment`.
  def change do
    alter table(:accounts) do
      add :fields, :jsonb, null: false, default: "[]"
    end
  end
end
