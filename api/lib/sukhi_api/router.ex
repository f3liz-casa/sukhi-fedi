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

  ## Authentication

  When a route is declared with a 4-tuple `{method, path, handler, opts}`
  and `opts` contains `scope: "<scope>"`, the router parses the
  `Authorization: Bearer <token>` header, calls
  `SukhiFedi.OAuth.verify_bearer/1` on the gateway, and rejects requests
  with 401 (no/invalid token), 403 (insufficient scope), or 503
  (gateway unreachable). On success, the bound account, app, and
  granted scopes are placed on `req[:assigns]` for the handler.
  """

  require Logger

  alias SukhiApi.{GatewayRpc, Registry}

  @gateway_oauth SukhiFedi.OAuth

  @spec handle(map()) :: {:ok, map()}
  def handle(%{} = req) do
    case find_route(req) do
      {:ok, handler, params, opts} ->
        req = Map.put(req, :path_params, params)

        case authenticate(req, opts) do
          {:ok, req} ->
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

          {:error, status, body} ->
            {:ok, json(status, body)}
        end

      :not_found ->
        {:ok, json(404, %{error: "not_found", path: Map.get(req, :path)})}
    end
  end

  defp find_route(req) do
    wanted_method = normalize_method(req[:method])
    wanted_path = req[:path] || ""

    Enum.find_value(Registry.routes(), :not_found, fn route ->
      {m, p, h, opts} = normalize_route(route)

      with true <- normalize_method(m) == wanted_method,
           {:ok, params} <- path_match(p, wanted_path) do
        {:ok, h, params, opts}
      else
        _ -> false
      end
    end)
  end

  defp normalize_route({m, p, h}), do: {m, p, h, []}
  defp normalize_route({m, p, h, opts}) when is_list(opts), do: {m, p, h, opts}

  defp normalize_method(m) when is_atom(m), do: m |> Atom.to_string() |> String.upcase()
  defp normalize_method(m) when is_binary(m), do: String.upcase(m)

  # ── auth ──────────────────────────────────────────────────────────────────

  defp authenticate(req, opts) do
    case Keyword.get(opts, :scope) do
      nil ->
        {:ok, req}

      required_scope when is_binary(required_scope) ->
        with {:ok, token} <- bearer_token(req),
             {:ok, {:ok, %{scopes: granted} = ctx}} <-
               GatewayRpc.call(@gateway_oauth, :verify_bearer, [token]),
             :ok <- check_scope(required_scope, granted) do
          assigns =
            req
            |> Map.get(:assigns, %{})
            |> Map.merge(%{
              current_account: ctx.account,
              current_app: ctx.app,
              scopes: granted
            })

          {:ok, Map.put(req, :assigns, assigns)}
        else
          {:error, :missing_token} ->
            {:error, 401, %{error: "invalid_token", error_description: "missing bearer token"}}

          {:ok, {:error, reason}} ->
            {:error, 401, %{error: "invalid_token", error_description: to_string(reason)}}

          {:error, :insufficient_scope} ->
            {:error, 403,
             %{
               error: "insufficient_scope",
               error_description: "this endpoint requires scope #{required_scope}",
               scope: required_scope
             }}

          {:error, :not_connected} ->
            {:error, 503, %{error: "gateway_not_connected"}}

          {:error, {:badrpc, reason}} ->
            {:error, 503, %{error: "gateway_rpc_failed", detail: inspect(reason)}}

          _ ->
            {:error, 401, %{error: "invalid_token"}}
        end
    end
  end

  defp bearer_token(req) do
    headers = req[:headers] || []

    case Enum.find(headers, fn {k, _} ->
           String.downcase(to_string(k)) == "authorization"
         end) do
      {_, value} ->
        case String.split(to_string(value), " ", parts: 2) do
          [scheme, token] ->
            if String.downcase(scheme) == "bearer" and token != "",
              do: {:ok, String.trim(token)},
              else: {:error, :missing_token}

          _ ->
            {:error, :missing_token}
        end

      nil ->
        {:error, :missing_token}
    end
  end

  defp check_scope(required, granted) when is_list(granted) do
    needed = String.split(required, ~r/\s+/, trim: true)
    if Enum.all?(needed, &(&1 in granted)), do: :ok, else: {:error, :insufficient_scope}
  end

  defp check_scope(_, _), do: {:error, :insufficient_scope}

  # ── path matching ─────────────────────────────────────────────────────────

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
