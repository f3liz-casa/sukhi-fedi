# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Router do
  @moduledoc """
  Entry point for `:rpc.call` from the gateway's `SukhiFedi.Web.PluginPlug`.

  Takes a request map (see `SukhiApi.Capability`), finds the matching
  route via `SukhiApi.Registry`, runs the handler, and returns a
  response map wrapped in `{:ok, _}`. Handler crashes are caught and
  converted to 500 responses so the gateway never sees `{:badrpc, _}`
  for anything other than a truly unreachable node.
  """

  require Logger

  alias SukhiApi.Registry

  @spec handle(map()) :: {:ok, map()}
  def handle(%{} = req) do
    case find_route(req) do
      {:ok, handler} ->
        try do
          handler.(req)
        rescue
          e ->
            Logger.error(
              "capability handler crashed: " <>
                Exception.format(:error, e, __STACKTRACE__)
            )

            {:ok, json(500, %{error: Exception.message(e)})}
        end

      :not_found ->
        {:ok, json(404, %{error: "not_found", path: Map.get(req, :path)})}
    end
  end

  defp find_route(req) do
    wanted_method = normalize_method(req[:method])
    wanted_path = req[:path] || ""

    Enum.find_value(Registry.routes(), :not_found, fn {m, p, h} ->
      if normalize_method(m) == wanted_method and path_match?(p, wanted_path) do
        {:ok, h}
      end
    end)
  end

  defp normalize_method(m) when is_atom(m), do: m |> Atom.to_string() |> String.upcase()
  defp normalize_method(m) when is_binary(m), do: String.upcase(m)

  # Exact-match routing for the MVP. A future iteration can add segment
  # extraction (`/api/v1/statuses/:id`) without breaking the behaviour.
  defp path_match?(pattern, path), do: pattern == path

  defp json(status, body_map) do
    %{
      status: status,
      body: Jason.encode!(body_map),
      headers: [{"content-type", "application/json"}]
    }
  end
end
