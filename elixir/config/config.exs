# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

config :sukhi_fedi, SukhiFedi.Repo,
  database: "sukhi_fedi",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :sukhi_fedi, ecto_repos: [SukhiFedi.Repo]

config :sukhi_fedi, Oban,
  repo: SukhiFedi.Repo,
  queues: [monitor: 5],
  plugins: [
    # Hourly NodeInfo monitor poll. PollCoordinator enumerates due
    # MonitoredInstances and enqueues one PollWorker per instance.
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", SukhiFedi.Addons.NodeinfoMonitor.PollCoordinator}
     ]}
  ]

config :sukhi_fedi, SukhiFedi.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

# Rate limiter (per-peer ETS buckets).
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       expiry_ms: 60_000 * 60 * 4,
       cleanup_interval_ms: 60_000 * 10
     ]}

import_config "#{config_env()}.exs"
