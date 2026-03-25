# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.ProfileController do
  import Plug.Conn
  alias SukhiFedi.{Accounts, Auth}

  def me(conn) do
    with {:ok, account} <- authenticate(conn) do
      send_json(conn, 200, serialize_account(account))
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
    end
  end

  def update(conn) do
    with {:ok, account} <- authenticate(conn),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         {:ok, updated} <- Accounts.update_profile(account, params) do
      send_json(conn, 200, serialize_account(updated))
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      {:error, %Ecto.Changeset{}} -> send_json(conn, 422, %{error: "validation_error", message: "Invalid profile data"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Bad request"})
    end
  end

  def show(conn) do
    username = conn.path_params["username"]
    
    case Accounts.get_account_by_username(username) do
      nil -> send_json(conn, 404, %{error: "not_found", message: "User not found"})
      account -> send_json(conn, 200, serialize_account(account))
    end
  end

  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Auth.verify_session(token)
      _ -> {:error, :unauthorized}
    end
  end

  defp serialize_account(account) do
    %{
      id: account.id,
      username: account.username,
      display_name: account.display_name,
      bio: account.bio,
      avatar_url: account.avatar_url,
      banner_url: account.banner_url,
      created_at: account.inserted_at
    }
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
