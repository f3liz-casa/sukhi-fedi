# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.BookmarkController do
  import Plug.Conn
  alias SukhiFedi.{Bookmarks, Auth}

  def create(conn) do
    with {:ok, account} <- authenticate(conn),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         {:ok, _} <- Bookmarks.create(account.id, params["note_id"]) do
      send_json(conn, 201, %{success: true})
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Failed to create bookmark"})
    end
  end

  def delete(conn) do
    with {:ok, account} <- authenticate(conn),
         note_id <- conn.path_params["note_id"] do
      Bookmarks.delete(account.id, note_id)
      send_resp(conn, 204, "")
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
    end
  end

  def list(conn) do
    with {:ok, account} <- authenticate(conn) do
      params = fetch_query_params(conn).params
      cursor = params["cursor"]
      limit = parse_int(params["limit"], 20)
      
      result = Bookmarks.list(account.id, cursor: cursor, limit: limit)
      send_json(conn, 200, result)
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
    end
  end

  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.verify_session(token)
      _ -> {:error, :unauthorized}
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(str, default) do
    case Integer.parse(str) do
      {int, _} -> int
      _ -> default
    end
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
