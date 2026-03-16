# SPDX-License-Identifier: MPL-2.0
import Config

config :sukhi_fedi, SukhiFedi.Repo,
  database: "sukhi_fedi",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :sukhi_fedi, Oban,
  repo: SukhiFedi.Repo,
  queues: [delivery: 10]

import_config "#{config_env()}.exs"
