# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

# Addon selection. ENABLED_ADDONS: comma list of ids, or "all" (default).
# DISABLE_ADDONS: comma list of ids to always exclude.
enabled_addons =
  case System.get_env("ENABLED_ADDONS", "all") do
    "all" -> :all
    "" -> :all
    csv -> csv |> String.split(",", trim: true) |> Enum.map(&String.to_atom/1)
  end

disabled_addons =
  System.get_env("DISABLE_ADDONS", "")
  |> String.split(",", trim: true)
  |> Enum.map(&String.to_atom/1)

config :sukhi_fedi, :enabled_addons, enabled_addons
config :sukhi_fedi, :disabled_addons, disabled_addons

if config_env() == :prod do
  config :sukhi_fedi, SukhiFedi.Repo,
    database: System.get_env("DB_NAME", "sukhi_fedi"),
    username: System.fetch_env!("DB_USER"),
    password: System.fetch_env!("DB_PASS"),
    hostname: System.get_env("DB_HOST", "localhost"),
    pool_size: String.to_integer(System.get_env("DB_POOL_SIZE", "10"))

  config :sukhi_fedi, :nats,
    host: System.get_env("NATS_HOST", "127.0.0.1"),
    port: String.to_integer(System.get_env("NATS_PORT", "4222"))

  # Distributed-Erlang plugin nodes reachable via `:rpc`.
  # Comma-separated list of `<name>@<host>` atoms. Nodes not reachable at
  # request time are skipped; if none are reachable, `/api/v1/*` returns
  # 503. Example: `PLUGIN_NODES=api@api,api_admin@api-admin`.
  config :sukhi_fedi, :plugin_nodes,
    System.get_env("PLUGIN_NODES", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.to_atom/1)
end
