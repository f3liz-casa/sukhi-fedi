# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Auth.PasswordController do
  @moduledoc """
  `POST /settings/password` — let a signed-in local account change its
  own password.

  The form lives in the SPA (`web/src/routes/settings/password`); this is
  the JSON endpoint behind it. Cookie-gated like `/login`: we read the
  `session_token` cookie, resolve it to an account, and require the
  current password before swapping in the new one. On success every
  session is revoked, so the SPA drops its token and sends the user back
  to `/login`.
  """

  import Plug.Conn

  alias SukhiFedi.{Accounts, LocalAccounts}

  @cookie "session_token"

  def submit(conn) do
    case current_account(conn) do
      nil ->
        json(conn, 401, %{error: "unauthorized"})

      account ->
        current = to_string(conn.body_params["current_password"] || "")
        new = to_string(conn.body_params["new_password"] || "")
        confirm = to_string(conn.body_params["confirm_password"] || "")

        cond do
          new != confirm ->
            json(conn, 422, %{error: "mismatch"})

          true ->
            case LocalAccounts.change_password(account, current, new) do
              {:ok, _} ->
                conn
                |> delete_resp_cookie(@cookie, path: "/")
                |> json(200, %{ok: true})

              {:error, :invalid_current} ->
                json(conn, 422, %{error: "current"})

              {:error, :password_too_short} ->
                json(conn, 422, %{error: "short"})
            end
        end
    end
  end

  defp current_account(conn) do
    conn = fetch_cookies(conn)
    Accounts.get_account_by_session_token(conn.cookies[@cookie] || "")
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(data))
  end
end
