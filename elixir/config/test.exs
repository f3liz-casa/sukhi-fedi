# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

config :sukhi_fedi, SukhiFedi.Repo,
  database: "sukhi_fedi_test",
  port: String.to_integer(System.get_env("DB_PORT", "15432")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :sukhi_fedi, Oban, testing: :inline

config :sukhi_fedi, :nats,
  host: System.get_env("NATS_HOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("NATS_PORT", "14222"))
