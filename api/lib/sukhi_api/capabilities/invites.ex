# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.Invites do
  @moduledoc """
  Public, read-only invite-code preview behind `GET /api/v1/invite/:code`.

  The SPA's `/invite/:code` landing page calls this to greet a visitor
  before signup — it reports whether the code is still good and who
  issued it. It never consumes the code; the claim happens inside
  `POST /api/v1/accounts` (the signup transaction). A dead or unknown
  code still returns 200 with `valid: false` so the landing page can
  greet gently rather than show an HTTP error — the `reason`
  (`invalid` / `already_used` / `expired`) only tunes the wording.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.GatewayRpc

  @impl true
  def routes do
    [{:get, "/api/v1/invite/:code", &show/1}]
  end

  def show(req) do
    code = req[:path_params]["code"] || ""

    case GatewayRpc.call(SukhiFedi.InviteCodes, :preview, [code]) do
      {:ok, {:ok, info}} ->
        ok(200, %{
          valid: true,
          issuer_handle: info.issuer_handle,
          issuer_display_name: info.issuer_display_name
        })

      {:ok, {:error, reason}} ->
        ok(200, %{valid: false, reason: to_string(reason)})

      {:error, :not_connected} ->
        ok(503, %{error: "gateway_not_connected"})

      {:error, {:badrpc, reason}} ->
        ok(503, %{error: "gateway_rpc_failed", detail: inspect(reason)})

      _ ->
        ok(500, %{error: "internal_error"})
    end
  end

  defp ok(status, body) do
    {:ok,
     %{
       status: status,
       body: JSON.encode!(body),
       headers: [{"content-type", "application/json"}]
     }}
  end
end
