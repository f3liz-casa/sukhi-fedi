# SPDX-License-Identifier: MPL-2.0
import Config

config :sukhi_fedi, SukhiFedi.Repo,
  database: "sukhi_fedi_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :sukhi_fedi, Oban, testing: :inline
