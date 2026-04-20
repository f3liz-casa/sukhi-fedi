# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

config :sukhi_delivery, SukhiDelivery.Repo,
  database: "sukhi_fedi_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :sukhi_delivery, Oban, testing: :inline
