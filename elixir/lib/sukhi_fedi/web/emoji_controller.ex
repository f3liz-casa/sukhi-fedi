# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.EmojiController do
  import Plug.Conn
  alias SukhiFedi.{Repo, Schema, Auth}

  def list(conn) do
    emojis = Repo.all(Schema.Emoji)
    send_json(conn, 200, Enum.map(emojis, &serialize_emoji/1))
  end

  def create(conn) do
    with {:ok, account} <- authenticate(conn),
         true <- is_admin?(account),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         {:ok, emoji} <- Schema.Emoji.changeset(%Schema.Emoji{}, params) |> Repo.insert() do
      send_json(conn, 201, serialize_emoji(emoji))
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      false -> send_json(conn, 403, %{error: "forbidden", message: "Admin access required"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Failed to create emoji"})
    end
  end

  def delete(conn) do
    with {:ok, account} <- authenticate(conn),
         true <- is_admin?(account),
         emoji_id <- conn.path_params["id"],
         emoji <- Repo.get(Schema.Emoji, emoji_id),
         true <- emoji != nil do
      Repo.delete(emoji)
      send_resp(conn, 204, "")
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      false -> send_json(conn, 403, %{error: "forbidden", message: "Admin access required"})
      _ -> send_json(conn, 404, %{error: "not_found", message: "Emoji not found"})
    end
  end

  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.verify_session(token)
      _ -> {:error, :unauthorized}
    end
  end

  defp is_admin?(account), do: account.role == "admin"

  defp serialize_emoji(emoji) do
    %{
      shortcode: emoji.shortcode,
      url: emoji.url,
      category: emoji.category
    }
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
