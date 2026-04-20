# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.PluginPlug do
  @moduledoc """
  Forwards the current request to a plugin node via distributed Erlang.

  The plugin catalogue lives under `api/` as an independent mix project
  (`:sukhi_api`). Each capability in `api/lib/sukhi_api/capabilities/`
  declares its own routes; see `SukhiApi.Capability`. Adding a new
  HTTP endpoint means dropping a new file into that directory — no
  gateway change needed.

  Operationally:

    * plugin node list read from `config :sukhi_fedi, :plugin_nodes`
    * first reachable node wins; unreachable nodes are skipped
    * `:rpc.call/5` with a 5s timeout
    * if nothing is reachable or the call fails, 503 is returned to
      the client
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @timeout 5_000

  @impl true
  def init(opts) do
    %{
      nodes: Keyword.get(opts, :nodes, :runtime),
      timeout: Keyword.get(opts, :timeout, @timeout),
      module: Keyword.get(opts, :module, SukhiApi.Router),
      function: Keyword.get(opts, :function, :handle)
    }
  end

  @impl true
  def call(conn, %{nodes: nodes_opt, timeout: timeout, module: mod, function: fun}) do
    nodes = resolve_nodes(nodes_opt)

    case reachable(nodes) do
      nil ->
        if nodes == [] do
          Logger.debug("PluginPlug: no plugin nodes configured")
        else
          Logger.warning("PluginPlug: no plugin nodes reachable (tried #{inspect(nodes)})")
        end

        send_err(conn, 503, "plugin_unavailable")

      node ->
        req = build_request(conn)

        case :rpc.call(node, mod, fun, [req], timeout) do
          {:ok, resp} ->
            respond(conn, resp)

          {:badrpc, reason} ->
            Logger.warning("PluginPlug: badrpc #{inspect(reason)} from #{node}")
            send_err(conn, 503, "plugin_rpc_failed")

          other ->
            Logger.warning("PluginPlug: unexpected response #{inspect(other)} from #{node}")
            send_err(conn, 500, "plugin_unexpected_response")
        end
    end
  end

  defp build_request(conn) do
    # `body_params` is already parsed by Plug.Parsers. Re-encode as JSON
    # so the plugin sees a uniform binary body regardless of the client's
    # content-type (JSON / form-urlencoded / multipart). Fine for the
    # Mastodon-compat surface which is predominantly JSON-in / JSON-out.
    body =
      case conn.body_params do
        %Plug.Conn.Unfetched{} -> ""
        %{} = m -> Jason.encode!(m)
        other -> to_string(other)
      end

    %{
      method: conn.method,
      path: conn.request_path,
      query: conn.query_string || "",
      headers: conn.req_headers,
      body: body
    }
  end

  defp resolve_nodes(:runtime),
    do: Application.get_env(:sukhi_fedi, :plugin_nodes, [])

  defp resolve_nodes(list) when is_list(list), do: list

  defp reachable(nodes) do
    Enum.find(nodes, fn node ->
      node in Node.list() or Node.connect(node) == true
    end)
  end

  defp respond(conn, %{status: status, body: body, headers: headers}) do
    conn =
      Enum.reduce(headers || [], conn, fn {k, v}, c ->
        put_resp_header(c, String.downcase(k), v)
      end)

    conn
    |> send_resp(status, body)
    |> halt()
  end

  defp respond(conn, other) do
    Logger.warning("PluginPlug: malformed response #{inspect(other)}")
    send_err(conn, 500, "plugin_response_malformed")
  end

  defp send_err(conn, status, code) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: code}))
    |> halt()
  end
end
