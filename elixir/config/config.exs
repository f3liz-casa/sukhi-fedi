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
  queues: [delivery: 10]

config :sukhi_fedi, SukhiFedi.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

config :opentelemetry,
  resource_detectors: [:otel_resource_env_var, :otel_resource_app_env],
  resource: %{service: %{name: "sukhi-fedi-elixir", version: "0.1.0"}}

config :opentelemetry, :processors,
  otel_batch_processor: %{exporter: {:opentelemetry_exporter, %{}}}

import_config "#{config_env()}.exs"
