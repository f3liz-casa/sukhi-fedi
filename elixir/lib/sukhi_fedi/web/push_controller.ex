# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.PushController do
  import Plug.Conn
  alias SukhiFedi.{WebPush, Auth}

  def subscribe(conn) do
    with {:ok, account} <- Auth.current_account(conn),
         %{"endpoint" => endpoint, "keys" => %{"p256dh" => p256dh, "auth" => auth}} <- conn.body_params do
      alerts = Map.get(conn.body_params, "alerts", %{})
      {:ok, _} = WebPush.subscribe(account.id, endpoint, p256dh, auth, alerts)
      send_resp(conn, 201, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "invalid request"}))
    end
  end

  def unsubscribe(conn) do
    with {:ok, _account} <- Auth.current_account(conn),
         %{"endpoint" => endpoint} <- conn.body_params do
      WebPush.unsubscribe(endpoint)
      send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
    else
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "invalid request"}))
    end
  end
end
