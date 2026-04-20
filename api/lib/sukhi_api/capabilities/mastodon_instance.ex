# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonInstance do
  @moduledoc """
  `GET /api/v1/instance` — Mastodon-compatible instance metadata.

  This is the example / MVP capability. Pattern to add more:
  drop a new file in `capabilities/`, `use SukhiApi.Capability`,
  implement `routes/0`, done.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  @impl true
  def routes, do: [{:get, "/api/v1/instance", &instance/1}]

  def instance(_req) do
    domain = Application.get_env(:sukhi_api, :domain, "localhost:4000")
    title = Application.get_env(:sukhi_api, :title, "sukhi-fedi")

    body = %{
      uri: domain,
      title: title,
      short_description: "ActivityPub server (sukhi-fedi)",
      description: "ActivityPub server (sukhi-fedi)",
      email: "",
      version: "4.0.0 (compatible; sukhi-fedi 0.1.0)",
      urls: %{streaming_api: "wss://#{domain}"},
      languages: ["en", "ja"],
      registrations: false,
      approval_required: false,
      invites_enabled: false,
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
