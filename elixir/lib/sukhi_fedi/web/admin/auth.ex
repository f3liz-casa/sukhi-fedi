# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Admin.Auth do
  @moduledoc """
  Helpers for the admin session.

  Auth model:
    - Admin pastes a Mastodon OAuth bearer token into `/admin/login`.
    - Server verifies via `SukhiFedi.OAuth.verify_bearer/1`, requires
      `account.is_admin = true`, and stores the raw token in the signed
      session cookie.
    - On every authenticated request, the bearer is re-verified — so
      revoking the OAuth token in the DB takes effect immediately
      without needing to invalidate every session cookie.
  """

  import Plug.Conn

  alias SukhiFedi.OAuth

  @doc """
  Verify the current session and return `{:ok, admin_account}` or
  `:error`. Always re-checks the DB so token revocation propagates
  without needing a session reset.
  """
  def current_admin(conn) do
    with token when is_binary(token) <- get_session(conn, :bearer),
         {:ok, %{account: %{is_admin: true} = account}} <- OAuth.verify_bearer(token) do
      {:ok, account}
    else
      _ -> :error
    end
  end

  @doc """
  Run `fun.(conn)` if the session belongs to an admin; otherwise 302 to
  `/admin/login`. `fun` receives a conn with `:admin` assigned.
  """
  def with_admin(conn, fun) do
    case current_admin(conn) do
      {:ok, admin} -> fun.(assign(conn, :admin, admin))
      :error -> redirect_to_login(conn)
    end
  end

  defp redirect_to_login(conn) do
    conn
    |> put_resp_header("location", "/admin/login")
    |> send_resp(302, "")
    |> halt()
  end
end
