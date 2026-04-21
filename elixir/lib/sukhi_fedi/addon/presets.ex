# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addon.Presets do
  @moduledoc """
  Named bundles of addon ids. Picked via the `ADDON_PRESETS` env var in
  `runtime.exs`; the expansion is unioned with `ENABLED_ADDONS` before
  being handed to `SukhiFedi.Addon.Registry`.

  KEEP IN SYNC with `SukhiApi.Addon.Presets` — the api plugin node has
  its own copy because it's a separate mix project.
  """

  @presets %{
    mastodon_compatible: [
      :mastodon_api,
      :media,
      :feeds,
      :moderation,
      :bookmarks,
      :pinned_notes,
      :streaming,
      :web_push
    ],
    server_version_watcher: [
      :nodeinfo_monitor,
      :feeds,
      :pinned_notes
    ]
  }

  @spec all() :: %{atom() => [atom()]}
  def all, do: @presets

  @spec get(atom()) :: [atom()]
  def get(id), do: Map.get(@presets, id, [])

  @spec expand([atom()]) :: [atom()]
  def expand(preset_ids) when is_list(preset_ids) do
    preset_ids
    |> Enum.flat_map(&get/1)
    |> Enum.uniq()
  end
end
