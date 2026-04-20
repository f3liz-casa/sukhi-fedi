# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

# Mirror the gateway's addon selection so capability routes disappear
# in lockstep with their owning addon.
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

config :sukhi_api, :enabled_addons, enabled_addons
config :sukhi_api, :disabled_addons, disabled_addons

if config_env() == :prod do
  config :sukhi_api,
    domain: System.get_env("DOMAIN", "localhost:4000"),
    title: System.get_env("INSTANCE_TITLE", "sukhi-fedi")

  # GATEWAY_NODE overrides the default gateway@elixir node for
  # `SukhiApi.GatewayRpc`.
  case System.get_env("GATEWAY_NODE") do
    nil ->
      :ok

    "" ->
      :ok

    node ->
      config :sukhi_api, :gateway_node, String.to_atom(node)
  end

  # Allowlist of capability modules. If unset (or empty), all compiled
  # capabilities run. Example:
  #   ENABLED_CAPABILITIES=Elixir.SukhiApi.Capabilities.MastodonInstance
  case System.get_env("ENABLED_CAPABILITIES") do
    nil ->
      :ok

    "" ->
      :ok

    list ->
      mods =
        list
        |> String.split(",", trim: true)
        |> Enum.map(&String.to_existing_atom/1)

      config :sukhi_api, :enabled_capabilities, mods
  end
end
