# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonInstance do
  @moduledoc """
  `GET /api/v1/instance` — Mastodon-compatible instance metadata.

  This is the example / MVP capability. Pattern to add more:
  drop a new file in `capabilities/`, `use SukhiApi.Capability`,
  implement `routes/0`, done.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  # Same VERSION file as :sukhi_fedi reads. Runtime lookup (not a
  # compile-time module attribute) because :sukhi_api isn't loaded
  # during its own compile, so the attribute would freeze in as nil.
  defp sukhi_version do
    case Application.spec(:sukhi_api, :vsn) do
      nil -> "0.0.0"
      vsn -> to_string(vsn)
    end
  end

  @impl true
  def routes, do: [{:get, "/api/v1/instance", &instance/1}]

  def instance(_req) do
    domain = SukhiApi.Config.domain!()
    title = Application.get_env(:sukhi_api, :title, "sukhi-fedi")

    body = %{
      uri: domain,
      title: title,
      short_description: "ActivityPub server (sukhi-fedi)",
      description: "ActivityPub server (sukhi-fedi)",
      email: "",
      version: "4.0.0 (compatible; sukhi-fedi #{sukhi_version()})",
      urls: %{streaming_api: "wss://#{domain}"},
      languages: ["en", "ja"],
      registrations: true,
      approval_required: false,
      invites_enabled: true,
      stats: %{user_count: 0, status_count: 0, domain_count: 0},
      contact_account: nil,
      rules: []
    }

    {:ok,
     %{
       status: 200,
       body: Jason.encode!(body),
       headers: [{"content-type", "application/json"}]
     }}
  end
end
