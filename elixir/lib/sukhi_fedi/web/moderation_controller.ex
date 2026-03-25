# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.ModerationController do
  import Plug.Conn
  alias SukhiFedi.{Moderation, Auth}

  def mute(conn) do
    with {:ok, account} <- Auth.current_account(conn),
         %{"target_id" => target_id} <- conn.body_params,
         expires_at <- Map.get(conn.body_params, "expires_at"),
         {:ok, _} <- Moderation.mute(account.id, target_id, expires_at) do
      send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "invalid request"}))
    end
  end

  def unmute(conn) do
    with {:ok, account} <- Auth.current_account(conn),
         %{"target_id" => target_id} <- conn.body_params do
      Moderation.unmute(account.id, target_id)
      send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "invalid request"}))
    end
  end

  def block(conn) do
    with {:ok, account} <- Auth.current_account(conn),
         %{"target_id" => target_id} <- conn.body_params,
         {:ok, _} <- Moderation.block(account.id, target_id) do
      send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "invalid request"}))
    end
  end

  def unblock(conn) do
    with {:ok, account} <- Auth.current_account(conn),
         %{"target_id" => target_id} <- conn.body_params do
      Moderation.unblock(account.id, target_id)
      send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "invalid request"}))
    end
  end

  def report(conn) do
    with {:ok, account} <- Auth.current_account(conn),
         params <- Map.put(conn.body_params, "account_id", account.id),
         {:ok, report} <- Moderation.create_report(params) do
      send_resp(conn, 201, Jason.encode!(%{id: report.id}))
    else
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "invalid request"}))
    end
  end
end
