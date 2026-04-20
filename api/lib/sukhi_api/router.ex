# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Router do
  @moduledoc """
  Entry point for `:rpc.call` from the gateway's `SukhiFedi.Web.PluginPlug`.

  Takes a request map (see `SukhiApi.Capability`), finds the matching
  route via `SukhiApi.Registry`, runs the handler, and returns a
  response map wrapped in `{:ok, _}`. Handler crashes are caught and
  converted to 500 responses so the gateway never sees `{:badrpc, _}`
  for anything other than a truly unreachable node.

  ## Path matching

  Routes support `:name` placeholder segments. For example, a route
  pattern of `/api/v1/monitors/:id` matches `/api/v1/monitors/42` and
  exposes `%{"id" => "42"}` to the handler via `req[:path_params]`.
  """

  require Logger

  alias SukhiApi.Registry

  @spec handle(map()) :: {:ok, map()}
  def handle(%{} = req) do
    case find_route(req) do
      {:ok, handler, params} ->
        req = Map.put(req, :path_params, params)

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
      with true <- normalize_method(m) == wanted_method,
           {:ok, params} <- path_match(p, wanted_path) do
        {:ok, h, params}
      else
        _ -> false
      end
    end)
  end

  defp normalize_method(m) when is_atom(m), do: m |> Atom.to_string() |> String.upcase()
  defp normalize_method(m) when is_binary(m), do: String.upcase(m)

  # Pattern matcher supporting `:name` placeholders.
  #   path_match("/foo/:id", "/foo/42") -> {:ok, %{"id" => "42"}}
  #   path_match("/foo", "/foo")        -> {:ok, %{}}
  #   path_match("/foo/:id", "/bar/42") -> :nomatch
  defp path_match(pattern, path) do
    pat_segs = String.split(pattern, "/", trim: true)
    path_segs = String.split(path, "/", trim: true)

    match_segments(pat_segs, path_segs, %{})
  end

  defp match_segments([], [], acc), do: {:ok, acc}
  defp match_segments([], _, _), do: :nomatch
  defp match_segments(_, [], _), do: :nomatch

  defp match_segments([":" <> name | rest_p], [seg | rest_s], acc) do
    match_segments(rest_p, rest_s, Map.put(acc, name, seg))
  end

  defp match_segments([seg | rest_p], [seg | rest_s], acc) do
    match_segments(rest_p, rest_s, acc)
  end

  defp match_segments(_, _, _), do: :nomatch

  defp json(status, body_map) do
    %{
      status: status,
      body: Jason.encode!(body_map),
      headers: [{"content-type", "application/json"}]
    }
  end
end
