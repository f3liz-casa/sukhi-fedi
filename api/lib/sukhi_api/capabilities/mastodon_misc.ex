# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonMisc do
  @moduledoc """
  Small read-only Mastodon endpoints that clients poll on startup. We
  don't persist per-user preferences or followed hashtags yet, so these
  return sensible defaults / empties — enough that clients like Elk and
  Phanpy stop erroring on a 404 right after login.

  When real per-user preferences / followed-tags land, replace the
  static bodies with gateway-backed reads.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  @impl true
  def routes do
    [
      {:get, "/api/v1/preferences", &preferences/1},
      {:get, "/api/v1/followed_tags", &followed_tags/1}
    ]
  end

  # Mastodon Preferences — posting/reading defaults. We don't store these
  # per user yet, so hand back the Mastodon defaults.
  def preferences(_req) do
    json(200, %{
      "posting:default:visibility" => "public",
      "posting:default:sensitive" => false,
      "posting:default:language" => nil,
      "reading:expand:media" => "default",
      "reading:expand:spoilers" => false
    })
  end

  # We don't support following hashtags yet — an empty list is the
  # correct, non-erroring answer.
  def followed_tags(_req), do: json(200, [])

  defp json(status, body) do
    {:ok,
     %{
       status: status,
       body: JSON.encode!(body),
       headers: [{"content-type", "application/json"}]
     }}
  end
end
