# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

config :sukhi_delivery, SukhiDelivery.Repo,
  database: "sukhi_fedi",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :sukhi_delivery, ecto_repos: [SukhiDelivery.Repo]

config :sukhi_delivery, Oban,
  repo: SukhiDelivery.Repo,
  queues: [delivery: 10, federation: 3],
  plugins: [Oban.Plugins.Pruner]

config :sukhi_delivery, SukhiDelivery.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

import_config "#{config_env()}.exs"
