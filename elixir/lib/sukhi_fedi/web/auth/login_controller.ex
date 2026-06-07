# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Auth.LoginController do
  @moduledoc """
  `POST /login` — validate username + password and mint the
  `session_token` cookie that `/oauth/authorize` consumes.

  The sign-in *form* now lives in the SPA (`web/src/routes/login`); this
  controller is the JSON endpoint behind it. The SPA POSTs credentials,
  we set the cookie on success, and the SPA walks the user on to
  `/check` → `/oauth/authorize` to obtain an OAuth token.

  Separate door from `/admin/login` (which takes a pre-issued bearer).
  """

  import Plug.Conn

  alias SukhiFedi.LocalAccounts

  @cookie "session_token"

  def submit(conn) do
    username = to_string(conn.body_params["username"] || "")
    password = to_string(conn.body_params["password"] || "")

    case LocalAccounts.authenticate(username, password) do
      {:ok, account} ->
        {:ok, token} = LocalAccounts.create_session(account)

        conn
        |> put_resp_cookie(@cookie, token,
          http_only: true,
          same_site: "Lax",
          secure: cookie_secure?(),
          max_age: 60 * 60 * 24 * 30,
          path: "/"
        )
        |> json(200, %{ok: true})

      {:error, :invalid} ->
        json(conn, 401, %{error: "invalid"})
    end
  end

  def logout(conn) do
    conn
    |> delete_resp_cookie(@cookie, path: "/")
    |> put_resp_header("location", "/")
    |> send_resp(302, "")
  end

  defp cookie_secure? do
    Application.get_env(:sukhi_fedi, :admin_session_secure, true)
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(data))
  end
end
