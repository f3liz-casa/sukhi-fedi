# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Auth.PasswordController do
  @moduledoc """
  The password's whole (optional, legacy) lifecycle for a signed-in
  local account:

      POST /settings/password          set (first time) or change
      POST /settings/password/remove   retire it ({password})

  Forms live in the SPA; these are the JSON endpoints, cookie-gated
  like `/login`. The password is one factor among several now:

  - An account *without* one may set it with just the session — adding
    a factor locks nobody out (email login keeps working) and a
    session thief gains nothing they don't already hold.
  - Changing an existing one still demands the current password and
    revokes every session/token (it may have been compromised).
  - Removing one demands the password itself and a verified email
    (`LocalAccounts.remove_password/1` refuses otherwise — no
    password and no email door would strand the account).
  """

  import Plug.Conn

  alias SukhiFedi.LocalAccounts
  alias SukhiFedi.Schema.Account
  alias SukhiFedi.Web.Auth.SessionCookie

  def submit(conn) do
    case SessionCookie.account(conn) do
      nil ->
        json(conn, 401, %{error: "unauthorized"})

      account ->
        new = to_string(conn.body_params["new_password"] || "")
        confirm = to_string(conn.body_params["confirm_password"] || "")

        if new != confirm do
          json(conn, 422, %{error: "mismatch"})
        else
          do_submit(conn, account, new)
        end
    end
  end

  # First password: nothing to verify against, no sessions to revoke.
  defp do_submit(conn, %Account{password_hash: nil} = account, new) do
    case LocalAccounts.set_initial_password(account, new) do
      {:ok, _} -> json(conn, 200, %{ok: true, initial: true})
      {:error, :password_too_short} -> json(conn, 422, %{error: "short"})
      {:error, :has_password} -> json(conn, 409, %{error: "has_password"})
    end
  end

  defp do_submit(conn, account, new) do
    current = to_string(conn.body_params["current_password"] || "")

    case LocalAccounts.change_password(account, current, new) do
      {:ok, _} ->
        conn
        |> SessionCookie.drop()
        |> json(200, %{ok: true})

      {:error, :invalid_current} ->
        json(conn, 422, %{error: "current"})

      {:error, :password_too_short} ->
        json(conn, 422, %{error: "short"})
    end
  end

  def remove(conn) do
    case SessionCookie.account(conn) do
      nil ->
        json(conn, 401, %{error: "unauthorized"})

      account ->
        with :ok <-
               LocalAccounts.check_password(account, to_string(conn.body_params["password"] || "")),
             {:ok, _} <- LocalAccounts.remove_password(account) do
          json(conn, 200, %{ok: true})
        else
          {:error, :invalid} -> json(conn, 403, %{error: "reauth"})
          {:error, :no_verified_email} -> json(conn, 409, %{error: "no_verified_email"})
        end
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(data))
  end
end
