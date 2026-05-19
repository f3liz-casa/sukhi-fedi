# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.DropUnusedApIdColumns do
  use Ecto.Migration

  @moduledoc """
  Columns that schemas declared but nothing in application code ever
  read or wrote:

    * `reactions.ap_id`  — outbound likes use the local outbox row id
      to mint an activity id; the reaction row itself doesn't need
      one. Will come back if/when remote `Like.id` is mirrored.
    * `boosts.ap_id`     — same story for boosts.
    * `notes.mfm`        — Misskey formatted-text field. Misskey
      native API surface is parked (OPEN_QUESTIONS Q3); when it
      ships the column comes back with a writer.
    * `notes.quote_of_ap_id` — Misskey quote-note reference. Same
      reason as mfm.

  Per session goal: no back-compat shims; the schemas drop the
  matching fields in the same change set.
  """

  def change do
    alter table(:reactions) do
      remove :ap_id, :string
    end

    alter table(:boosts) do
      remove :ap_id, :string
    end

    alter table(:notes) do
      remove :mfm, :string
      remove :quote_of_ap_id, :string
    end

    # Index over the column we just dropped.
    drop_if_exists index(:notes, [:quote_of_ap_id])
  end
end
