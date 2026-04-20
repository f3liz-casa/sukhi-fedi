# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.SocialController do
  import Plug.Conn
  alias SukhiFedi.{Social, Auth, Accounts}

  def update_relationship(conn) do
    with {:ok, account} <- authenticate(conn),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} <- Jason.decode(body),
         target_id <- conn.path_params["id"],
         target <- Accounts.get_account(target_id),
         true <- target != nil,
         {:ok, relationship} <- apply_relationship_changes(account, target, params) do
      send_json(conn, 200, relationship)
    else
      {:error, :unauthorized} -> send_json(conn, 401, %{error: "invalid_token", message: "Unauthorized"})
      false -> send_json(conn, 404, %{error: "not_found", message: "User not found"})
      _ -> send_json(conn, 400, %{error: "invalid_request", message: "Bad request"})
    end
  end

  def followers(conn) do
    username = conn.path_params["username"]
    
    case Accounts.get_account_by_username(username) do
      nil -> send_json(conn, 404, %{error: "not_found", message: "User not found"})
      account ->
        params = fetch_query_params(conn).params
        opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
        result = Social.list_followers(account.id, opts)
        send_json(conn, 200, result)
    end
  end

  def following(conn) do
    username = conn.path_params["username"]

    case Accounts.get_account_by_username(username) do
      nil -> send_json(conn, 404, %{error: "not_found", message: "User not found"})
      account ->
        params = fetch_query_params(conn).params
        opts = [cursor: params["cursor"], limit: parse_int(params["limit"], 20)]
        follower_uri = "https://#{Application.get_env(:sukhi_fedi, :domain)}/users/#{account.username}"
        result = Social.list_following(follower_uri, opts)
        send_json(conn, 200, result)
    end
  end

  defp apply_relationship_changes(account, target, params) do
    follower_uri = "https://#{Application.get_env(:sukhi_fedi, :domain)}/users/#{account.username}"
    
    # Handle follow
    if Map.has_key?(params, "follow") do
      if params["follow"] do
        Social.follow(follower_uri, target.id)
      else
        Social.unfollow(follower_uri, target.id)
      end
    end
    
    # Handle mute
    if Map.has_key?(params, "mute") do
      if params["mute"] do
        Social.mute(account.id, target.id)
      else
        Social.unmute(account.id, target.id)
      end
    end
    
    # Handle block
    if Map.has_key?(params, "block") do
      if params["block"] do
        Social.block(account.id, target.id)
      else
        Social.unblock(account.id, target.id)
      end
    end
    
    {:ok, %{
      following: Social.following?(account.id, target.id),
      muting: Social.muting?(account.id, target.id),
      blocking: Social.blocking?(account.id, target.id)
    }}
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
