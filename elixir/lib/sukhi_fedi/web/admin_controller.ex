# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.AdminController do
  import Plug.Conn
  alias SukhiFedi.Auth
  alias SukhiFedi.Addons.Moderation

  defp require_admin(conn) do
    with {:ok, account} <- Auth.current_account(conn),
         true <- account.is_admin do
      {:ok, account}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def list_reports(conn) do
    with {:ok, _admin} <- require_admin(conn) do
      status = conn.query_params["status"] || "open"
      reports = Moderation.list_reports(status)
      send_resp(conn, 200, Jason.encode!(reports))
    else
      _ -> send_resp(conn, 403, Jason.encode!(%{error: "unauthorized"}))
    end
  end

  def resolve_report(conn) do
    with {:ok, admin} <- require_admin(conn),
         %{"id" => id} <- conn.path_params,
         {:ok, _} <- Moderation.resolve_report(String.to_integer(id), admin.id) do
      send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 403, Jason.encode!(%{error: "unauthorized"}))
    end
  end

  def block_instance(conn) do
    with {:ok, admin} <- require_admin(conn),
         %{"domain" => domain} <- conn.body_params do
      severity = Map.get(conn.body_params, "severity", "suspend")
      reason = Map.get(conn.body_params, "reason", "")
      Moderation.block_instance(domain, severity, reason, admin.id)
      send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 403, Jason.encode!(%{error: "unauthorized"}))
    end
  end

  def unblock_instance(conn) do
    with {:ok, _admin} <- require_admin(conn),
         %{"domain" => domain} <- conn.path_params do
      Moderation.unblock_instance(domain)
      send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 403, Jason.encode!(%{error: "unauthorized"}))
    end
  end

  def list_instance_blocks(conn) do
    with {:ok, _admin} <- require_admin(conn) do
      blocks = Moderation.list_instance_blocks()
      send_resp(conn, 200, Jason.encode!(blocks))
    else
      _ -> send_resp(conn, 403, Jason.encode!(%{error: "unauthorized"}))
    end
  end

  def suspend_account(conn) do
    with {:ok, admin} <- require_admin(conn),
         %{"id" => id} <- conn.path_params,
         reason <- Map.get(conn.body_params, "reason", ""),
         {:ok, _} <- Moderation.suspend_account(String.to_integer(id), admin.id, reason) do
      send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 403, Jason.encode!(%{error: "unauthorized"}))
    end
  end

  def unsuspend_account(conn) do
    with {:ok, _admin} <- require_admin(conn),
         %{"id" => id} <- conn.path_params,
         {:ok, _} <- Moderation.unsuspend_account(String.to_integer(id)) do
      send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 403, Jason.encode!(%{error: "unauthorized"}))
    end
  end
end
