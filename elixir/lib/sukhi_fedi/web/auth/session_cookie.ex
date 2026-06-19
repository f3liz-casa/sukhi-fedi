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
  alias SukhiFedi.Web.RateLimitPlug

  @cookie "session_token"
  @max_age 60 * 60 * 24 * 30

  @spec mint(Plug.Conn.t(), SukhiFedi.Schema.Account.t()) :: Plug.Conn.t()
  def mint(conn, account) do
    {:ok, token} = LocalAccounts.create_session(account, device_context(conn))

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

  @doc """
  The SHA-256 hash of the request's session cookie, or nil. The session
  list uses it to mark which row is *this* device — never the plaintext
  token, which only ever lives in the cookie.
  """
  @spec current_token_hash(Plug.Conn.t()) :: String.t() | nil
  def current_token_hash(conn) do
    conn = fetch_cookies(conn)

    case conn.cookies[@cookie] do
      token when is_binary(token) and token != "" ->
        :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

      _ ->
        nil
    end
  end

  # The device behind this login, for the session row + new-device
  # heads-up. The IP comes from the one shared resolver (`peer_id/1`),
  # never a second copy of the cf-connecting-ip dance.
  defp device_context(conn) do
    ua =
      case get_req_header(conn, "user-agent") do
        [value | _] when is_binary(value) -> value
        _ -> nil
      end

    %{ip_text: RateLimitPlug.peer_id(conn), user_agent: ua}
  end

  defp secure? do
    Application.get_env(:sukhi_fedi, :admin_session_secure, true)
  end
end
