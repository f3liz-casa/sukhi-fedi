# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.MediaController do
  import Plug.Conn
  alias SukhiFedi.{Repo, Schema, Auth}
  alias SukhiFedi.Addons.Media

  def presigned(conn) do
    with {:ok, account} <- authenticate(conn),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         {:ok, result} <- Media.generate_upload_url(
           account.id,
           params["filename"],
           params["mime_type"],
           params["size"]
         ) do
      send_json(conn, 200, result)
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Invalid request"})
    end
  end

  def register(conn) do
    with {:ok, account} <- authenticate(conn),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         attrs <- Map.put(params, "account_id", account.id),
         {:ok, media} <- Media.create_media(attrs) do
      send_json(conn, 201, serialize_media(media))
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Failed to create media"})
    end
  end

  def list(conn) do
    with {:ok, account} <- authenticate(conn) do
      params = fetch_query_params(conn).params
      opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
      result = Media.list_by_account(account.id, opts)
      send_json(conn, 200, result)
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
    end
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

  defp serialize_media(media) do
    %{
      id: media.id,
      url: media.url,
      thumbnail_url: media.thumbnail_url,
      mime_type: media.mime_type,
      blurhash: media.blurhash,
      description: media.description,
      sensitive: media.sensitive
    }
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
