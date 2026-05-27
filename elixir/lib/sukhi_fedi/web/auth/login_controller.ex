# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Auth.LoginController do
  @moduledoc """
  `/login` — the user-facing sign-in page that mints the
  `session_token` cookie used by `/oauth/authorize`.

  This is a separate door from `/admin/login` (which accepts a
  pre-issued OAuth bearer for back-office work). End users land here
  from the SPA, type username + password, and get bounced back to
  whichever URL the `next` query param points at — typically
  `/oauth/authorize?...` so the OAuth code flow can resume.
  """

  import Plug.Conn

  alias SukhiFedi.LocalAccounts

  @cookie "session_token"

  # ホームから直接来たときは next が無いので、デフォルトで
  # /check?intent=login に渡す。これでログイン → Anubis →
  # OAuth フローの順に進む。/oauth/authorize から redirect されて
  # きたときは next にその URL が入っているので、そちらが優先。
  @default_next "/check?intent=login"

  def show(conn) do
    next = conn.query_params["next"] || @default_next
    error = conn.query_params["error"]

    html = render_login(next: next, error: error, username: "")

    conn
    |> put_resp_content_type("text/html; charset=utf-8")
    |> send_resp(200, html)
  end

  def submit(conn) do
    %{"username" => username, "password" => password} = conn.body_params
    next = (conn.body_params["next"] || @default_next) |> safe_next()

    case LocalAccounts.authenticate(to_string(username), to_string(password)) do
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
        |> redirect(next)

      {:error, :invalid} ->
        redirect(conn, "/login?next=#{URI.encode_www_form(next)}&error=invalid")
    end
  end

  def logout(conn) do
    conn
    |> delete_resp_cookie(@cookie, path: "/")
    |> redirect("/")
  end

  defp redirect(conn, location) do
    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
  end

  defp safe_next("/" <> _ = path), do: path
  defp safe_next(_), do: "/"

  defp cookie_secure? do
    Application.get_env(:sukhi_fedi, :admin_session_secure, true)
  end

  defp render_login(opts) do
    next = Keyword.fetch!(opts, :next)
    error = Keyword.get(opts, :error)
    username = Keyword.get(opts, :username, "")

    error_html =
      case error do
        nil -> ""
        _ -> ~s|<p class="error">名前か合言葉が、見つかりませんでした。</p>|
      end

    """
    <!doctype html>
    <html lang="ja">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>入る — sukhi-fedi</title>
      <link rel="stylesheet" href="/static/styles/app.css" />
    </head>
    <body>
      <main class="wrap stack">
        <section class="hero">
          <h1>入る</h1>
          <p class="tagline">あなたの名前と、合言葉を、おしえてください。</p>
        </section>
        #{error_html}
        <form method="post" action="/login" class="form stack">
          <input type="hidden" name="next" value="#{escape(next)}" />
          <label class="stack-tight">
            <span>なまえ</span>
            <input type="text" name="username" value="#{escape(username)}" autocomplete="username" autofocus required />
          </label>
          <label class="stack-tight">
            <span>あいことば</span>
            <input type="password" name="password" autocomplete="current-password" required />
          </label>
          <button type="submit">入る</button>
        </form>
        <p class="prose-small"><a href="/">いえ、まだはじめての人は、こちらへ。</a></p>
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
