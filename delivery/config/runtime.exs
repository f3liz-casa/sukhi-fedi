# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

if config_env() == :prod do
  config :sukhi_delivery, SukhiDelivery.Repo,
    database: System.get_env("DB_NAME", "sukhi_fedi"),
    username: System.fetch_env!("DB_USER"),
    password: System.fetch_env!("DB_PASS"),
    hostname: System.get_env("DB_HOST", "localhost"),
    pool_size: String.to_integer(System.get_env("DB_POOL_SIZE", "5"))

  config :sukhi_delivery, :nats,
    host: System.get_env("NATS_HOST", "127.0.0.1"),
    port: String.to_integer(System.get_env("NATS_PORT", "4222"))

  config :sukhi_delivery, :metrics_port,
    String.to_integer(System.get_env("METRICS_PORT", "4001"))
end
