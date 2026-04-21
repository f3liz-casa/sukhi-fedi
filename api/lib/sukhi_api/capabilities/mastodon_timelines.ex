# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Capabilities.MastodonTimelines do
  @moduledoc """
  Mastodon `/api/v1/timelines/*` capability.

      GET /api/v1/timelines/home    scope: read:statuses (authenticated)
      GET /api/v1/timelines/public  (public)

  PR3 ships home + public; tag/list/direct timelines deferred.
  """

  use SukhiApi.Capability, addon: :mastodon_api

  alias SukhiApi.{GatewayRpc, Pagination}
  alias SukhiApi.Views.MastodonStatus

  @impl true
  def routes do
    [
      {:get, "/api/v1/timelines/home", &home/1, scope: "read:statuses"},
      {:get, "/api/v1/timelines/public", &public/1}
    ]
  end

  def home(req) do
    %{current_account: viewer} = req[:assigns]
    opts = Pagination.parse_opts(req[:query])

    case viewer do
      nil ->
        ok(403, %{error: "this endpoint requires a user-bound token"})

      %{} = v ->
        case GatewayRpc.call(SukhiFedi.Timelines, :home, [v, Map.to_list(opts)]) do
          {:ok, notes} when is_list(notes) ->
            render_page(notes, "/api/v1/timelines/home", opts)

          {:error, :not_connected} ->
            ok(503, %{error: "gateway_not_connected"})

          {:error, {:badrpc, r}} ->
            ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})

          _ ->
            ok(500, %{error: "internal_error"})
        end
    end
  end

  def public(req) do
    base_opts = Pagination.parse_opts(req[:query])
    parsed = parse_query(req[:query])

    opts =
      base_opts
      |> Map.put(:only_media, parsed["only_media"] in ["true", "1"])
      |> Map.put(:local, parsed["local"] in ["true", "1", nil])
      |> Map.put(:remote, parsed["remote"] in ["true", "1"])

    case GatewayRpc.call(SukhiFedi.Timelines, :public, [Map.to_list(opts)]) do
      {:ok, notes} when is_list(notes) ->
        render_page(notes, "/api/v1/timelines/public", opts)

      {:error, :not_connected} ->
        ok(503, %{error: "gateway_not_connected"})

      {:error, {:badrpc, r}} ->
        ok(503, %{error: "gateway_rpc_failed", detail: inspect(r)})

      _ ->
        ok(500, %{error: "internal_error"})
    end
  end

  defp render_page(notes, base_url, opts) do
    body = Enum.map(notes, &MastodonStatus.render/1)
    headers = [{"content-type", "application/json"}]

    headers =
      case Pagination.link_header(base_url, notes, & &1.id, opts) do
        nil -> headers
        link -> [link | headers]
      end

    {:ok, %{status: 200, body: Jason.encode!(body), headers: headers}}
  end

  defp parse_query(nil), do: %{}
  defp parse_query(""), do: %{}
  defp parse_query(q) when is_binary(q), do: URI.decode_query(q)

  defp ok(status, body) do
    {:ok,
     %{
       status: status,
       body: Jason.encode!(body),
       headers: [{"content-type", "application/json"}]
     }}
  end
end
