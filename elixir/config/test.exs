# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

config :sukhi_fedi, SukhiFedi.Repo,
  database: "sukhi_fedi_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :sukhi_fedi, Oban, testing: :inline
