# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.DropLegacyObjectsAndArticles do
  use Ecto.Migration

  @moduledoc """
  Retires three tables that no production code reads or writes:

    * `deliveries` — pre-outbox-pattern outbound queue. Replaced by
      Oban + `delivery_receipts`. Held a FK to `objects`.
    * `objects`    — raw JSON-LD mirror of every inbound activity.
      Replaced by the `notes` mirror written from
      `AP.Instructions.maybe_mirror_create_note/1`.
    * `articles`   — long-form posts. Never wired into the REST surface
      and the addon was the only writer.

  No backwards-compat shim: per session goal, legacy is being
  excised, not preserved.
  """

  def change do
    # `deliveries` carries a FK to `objects`; must drop first.
    drop_if_exists table(:deliveries)
    drop_if_exists table(:objects)
    drop_if_exists table(:articles)
  end
end
