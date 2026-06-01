# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Auth.PasswordController do
  @moduledoc """
  `/settings/password` — let a signed-in local account change its own
  password.

  Same door as `/login`: we read the `session_token` cookie, resolve it
  to an account, and require a fresh re-entry of the current password
  before swapping in the new one. No bearer / OAuth here; this is the
  plain session-cookie surface that login mints.
  """

  import Plug.Conn

  alias SukhiFedi.{Accounts, LocalAccounts}

  @cookie "session_token"
  @login_next "/login?next=" <> "/settings/password"

  def show(conn) do
    case current_account(conn) do
      nil ->
        redirect(conn, @login_next)

      account ->
        html = render_form(account: account, error: conn.query_params["error"])

        conn
        |> put_resp_content_type("text/html; charset=utf-8")
        |> send_resp(200, html)
    end
  end

  def submit(conn) do
    case current_account(conn) do
      nil ->
        redirect(conn, @login_next)

      account ->
        current = to_string(conn.body_params["current_password"] || "")
        new = to_string(conn.body_params["new_password"] || "")
        confirm = to_string(conn.body_params["confirm_password"] || "")

        cond do
          new != confirm ->
            redirect(conn, "/settings/password?error=mismatch")

          true ->
            case LocalAccounts.change_password(account, current, new) do
              # On success every session — including this one — is revoked,
              # so we can't bounce back to the cookie-gated form. Drop the
              # now-stale cookie and render the "done, sign in again" page
              # directly.
              {:ok, _} ->
                conn
                |> delete_resp_cookie(@cookie, path: "/")
                |> put_resp_content_type("text/html; charset=utf-8")
                |> send_resp(200, render_done())

              {:error, :invalid_current} -> redirect(conn, "/settings/password?error=current")
              {:error, :password_too_short} -> redirect(conn, "/settings/password?error=short")
            end
        end
    end
  end

  defp current_account(conn) do
    conn = fetch_cookies(conn)
    Accounts.get_account_by_session_token(conn.cookies[@cookie] || "")
  end

  defp redirect(conn, location) do
    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
  end

  defp render_done do
    """
    <!doctype html>
    <html lang="ja">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>変わりました — sukhi-fedi</title>
      <link rel="stylesheet" href="/static/styles/app.css" />
    </head>
    <body>
      <main class="wrap stack">
        <section class="hero">
          <h1>変わりました</h1>
          <p class="tagline">あたらしい合言葉に、なりました。</p>
        </section>
        <p class="notice">いちど、ぜんぶの端末からログアウトしました。あたらしい合言葉で、もういちど入ってください。</p>
        <p><a href="/login?next=/timeline">入る</a></p>
      </main>
    </body>
    </html>
    """
  end

  defp render_form(opts) do
    account = Keyword.fetch!(opts, :account)
    error = Keyword.get(opts, :error)

    notice =
      cond do
        error == "current" -> ~s|<p class="error">いまの合言葉が、ちがうみたいです。</p>|
        error == "mismatch" -> ~s|<p class="error">新しい合言葉が、二つで揃っていません。</p>|
        error == "short" -> ~s|<p class="error">合言葉は、8文字以上にしてください。</p>|
        true -> ""
      end

    """
    <!doctype html>
    <html lang="ja">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>合言葉を変える — sukhi-fedi</title>
      <link rel="stylesheet" href="/static/styles/app.css" />
    </head>
    <body>
      <main class="wrap stack">
        <section class="hero">
          <h1>合言葉を変える</h1>
          <p class="tagline">@#{escape(account.username)} の合言葉を、あたらしくします。</p>
        </section>
        #{notice}
        <form method="post" action="/settings/password" class="form stack">
          <label class="stack-tight">
            <span>いまの合言葉</span>
            <input type="password" name="current_password" autocomplete="current-password" required />
          </label>
          <label class="stack-tight">
            <span>あたらしい合言葉（8文字以上）</span>
            <input type="password" name="new_password" autocomplete="new-password" minlength="8" required />
          </label>
          <label class="stack-tight">
            <span>もういちど、あたらしい合言葉</span>
            <input type="password" name="confirm_password" autocomplete="new-password" minlength="8" required />
          </label>
          <button type="submit">変える</button>
        </form>
        <p class="prose-small"><a href="/timeline">もどる</a></p>
      </main>
    </body>
    </html>
    """
  end

  defp escape(nil), do: ""
  defp escape(v) do
    v
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
