# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.FeedsController do
  import Plug.Conn
  alias SukhiFedi.{Feeds, Auth}

  def show(conn) do
    urn = conn.path_params["urn"]
    
    case urn do
      "home" -> home_feed(conn)
      "local" -> local_feed(conn)
      "public" -> public_feed(conn)
      _ -> send_json(conn, 404, %{error: "not_found", message: "Feed not found"})
    end
  end

  defp home_feed(conn) do
    with {:ok, account} <- authenticate(conn) do
      opts = parse_pagination_opts(conn)
      result = Feeds.home_feed(account.id, opts)
      send_json(conn, 200, result)
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
    end
  end

  defp local_feed(conn) do
    opts = parse_pagination_opts(conn)
    result = Feeds.local_feed(opts)
    send_json(conn, 200, result)
  end

  defp public_feed(conn) do
    opts = parse_pagination_opts(conn)
    result = Feeds.public_feed(opts)
    send_json(conn, 200, result)
  end

  defp parse_pagination_opts(conn) do
    params = fetch_query_params(conn).params
    [
      limit: parse_int(params["limit"], 20),
      cursor: params["cursor"]
    ]
  end

  defp parse_int(nil, default), do: default
  defp parse_int(str, default) do
    case Integer.parse(str) do
      {int, _} -> int
      _ -> default
    end
  end

  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.verify_session(token)
      _ -> {:error, :unauthorized}
    end
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
