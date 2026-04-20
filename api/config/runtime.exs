# SPDX-License-Identifier: AGPL-3.0-or-later
import Config

if config_env() == :prod do
  config :sukhi_api,
    domain: System.get_env("DOMAIN", "localhost:4000"),
    title: System.get_env("INSTANCE_TITLE", "sukhi-fedi")

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
