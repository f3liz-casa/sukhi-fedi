# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Registry do
  @moduledoc """
  Discovers modules that `use SukhiApi.Capability` within the
  `:sukhi_api` application, optionally filtered by the
  `:enabled_capabilities` config key.

  `:enabled_capabilities` values:

    * `:all` (default) — every compiled capability is active
    * `[Mod1, Mod2]`   — explicit allowlist (others are ignored)
  """

  @spec capabilities() :: [module()]
  def capabilities do
    case :application.get_key(:sukhi_api, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.filter(&capability?/1)
        |> filter_enabled()

      _ ->
        []
    end
  end

  @spec routes() :: [SukhiApi.Capability.route()]
  def routes do
    Enum.flat_map(capabilities(), & &1.routes())
  end

  defp capability?(mod) do
    try do
      Keyword.has_key?(mod.module_info(:attributes), :sukhi_api_capability)
    rescue
      _ -> false
    end
  end

  defp filter_enabled(mods) do
    case Application.get_env(:sukhi_api, :enabled_capabilities, :all) do
      :all -> mods
      list when is_list(list) -> Enum.filter(mods, &(&1 in list))
    end
  end
end
