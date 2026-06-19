# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule Mix.Tasks.Sukhi.Migrate do
  @moduledoc """
  Dev equivalent of `SukhiFedi.Release.migrate_all/0`.

  Walks `priv/repo/migrations/core/` and each enabled addon's migration
  path. Replaces `mix ecto.migrate` in this project because migrations
  are spread across addon subdirs.

  Inherits `SukhiFedi.Release.check_migration_sanity/0` (it runs inside
  `migrate_all/0`), so dev refuses an out-of-order schema the same way the
  release entrypoint does.
  """

  use Mix.Task

  @shortdoc "Run core and addon migrations"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    SukhiFedi.Release.migrate_all()
  end
end
