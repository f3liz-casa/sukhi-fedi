# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Creates the `oban_jobs` table (and supporting indexes / triggers).
  # Until now, unit tests ran with `config :..., Oban, testing: :inline`
  # which never touches the table — so the lack of an explicit migration
  # went unnoticed. With the delivery node taking over the :delivery queue
  # via cross-node Oban, both the gateway and delivery point at the same
  # shared table and it must exist before either supervisor starts.
  def up, do: Oban.Migrations.up()

  def down, do: Oban.Migrations.down(version: 1)
end
