# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Auth.SessionCookie do
  @moduledoc """
  The `session_token` cookie, in one place: every login door (password,
  email code, passkey, TOTP step) mints it here with the same flags,
  and the management endpoints resolve it back to an account here.

  This cookie is the *first-party* proof. OAuth bearers — which any
  third-party app can hold — are deliberately not accepted where this
  module is the gate: a leaked bearer must not be able to re-wire the
  account's login factors.
  """

  import Plug.Conn

  alias SukhiFedi.{Accounts, LocalAccounts}

  @cookie "session_token"
  @max_age 60 * 60 * 24 * 30

  @spec mint(Plug.Conn.t(), SukhiFedi.Schema.Account.t()) :: Plug.Conn.t()
  def mint(conn, account) do
    {:ok, token} = LocalAccounts.create_session(account)

    put_resp_cookie(conn, @cookie, token,
      http_only: true,
      same_site: "Lax",
      secure: secure?(),
      max_age: @max_age,
      path: "/"
    )
  end

  @spec drop(Plug.Conn.t()) :: Plug.Conn.t()
  def drop(conn), do: delete_resp_cookie(conn, @cookie, path: "/")

  @doc "The signed-in account behind the request's cookie, or nil."
  @spec account(Plug.Conn.t()) :: SukhiFedi.Schema.Account.t() | nil
  def account(conn) do
    conn = fetch_cookies(conn)
    Accounts.get_account_by_session_token(conn.cookies[@cookie] || "")
  end

  defp secure? do
    Application.get_env(:sukhi_fedi, :admin_session_secure, true)
  end
end
