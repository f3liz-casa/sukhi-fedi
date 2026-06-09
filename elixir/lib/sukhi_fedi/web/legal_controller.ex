# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.LegalController do
  @moduledoc """
  Serves the static legal pages — terms of service and privacy policy.

  Robust by construction: the Markdown sources in `priv/legal/` are rendered
  to HTML **at compile time** and baked into the release, so serving them at
  runtime is just sending a constant string — no Markdown parsing, no JS, no
  database, no SPA. If a source has a syntax error the build fails (it never
  reaches production). The page is fully self-contained (inline CSS, no
  external fonts/CDN), so it renders even if everything else is down.

  Update the docs by editing `priv/legal/*.ko.md` and rebuilding.
  """
  import Plug.Conn

  @privacy_path Path.expand("../../../priv/legal/privacy.ko.md", __DIR__)
  @terms_path Path.expand("../../../priv/legal/terms.ko.md", __DIR__)

  # Recompile when a source changes.
  @external_resource @privacy_path
  @external_resource @terms_path

  @privacy_body Earmark.as_html!(File.read!(@privacy_path), %Earmark.Options{gfm: true, breaks: false})
  @terms_body Earmark.as_html!(File.read!(@terms_path), %Earmark.Options{gfm: true, breaks: false})

  @css """
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin: 0; line-height: 1.7; color: #222; background: #fafafa;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans KR", "Noto Sans JP", Roboto, sans-serif; }
  .nav, .legal, .foot { max-width: 720px; margin: 0 auto; padding-left: 1.25rem; padding-right: 1.25rem; }
  .nav { padding-top: 1.1rem; font-size: .9rem; }
  .nav a { color: #777; text-decoration: none; margin-right: 1rem; }
  .nav a:hover { text-decoration: underline; }
  .legal { padding: 1.5rem 1.25rem 3rem; }
  .legal h1 { font-size: 1.7rem; line-height: 1.3; margin: .5rem 0 1rem; }
  .legal h2 { font-size: 1.25rem; margin: 2.2rem 0 .6rem; }
  .legal h3 { font-size: 1.05rem; margin: 1.4rem 0 .4rem; }
  .legal a { color: #2563eb; text-underline-offset: 2px; }
  .legal hr { border: none; border-top: 1px solid #e3e3e3; margin: 2rem 0; }
  .legal table { border-collapse: collapse; width: 100%; margin: 1rem 0; font-size: .95rem; display: block; overflow-x: auto; }
  .legal th, .legal td { border: 1px solid #ddd; padding: .5rem .7rem; text-align: left; vertical-align: top; }
  .legal th { background: #f0f0f0; }
  .legal blockquote { margin: 1rem 0; padding: .3rem 1rem; border-left: 3px solid #cbd5e1; color: #555; background: #f5f7fa; border-radius: 0 6px 6px 0; }
  .legal pre { background: #f0f0f0; padding: 1rem; border-radius: 8px; overflow-x: auto; font-size: .85rem; line-height: 1.5; }
  .legal code { background: #f0f0f0; padding: .1rem .3rem; border-radius: 4px; font-size: .9em;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  .legal pre code { background: none; padding: 0; }
  .foot { padding: 1.5rem 1.25rem 3rem; border-top: 1px solid #e3e3e3; font-size: .9rem; color: #888; }
  .foot a { color: #666; }
  @media (prefers-color-scheme: dark) {
    body { color: #dcdde0; background: #16181c; }
    .legal a { color: #7aa2f7; }
    .legal hr, .foot { border-color: #2a2e37; }
    .legal th, .legal td { border-color: #333; }
    .legal th { background: #20242c; }
    .legal blockquote { color: #aab; background: #1c2027; border-left-color: #3a4150; }
    .legal pre, .legal code { background: #20242c; }
    .nav a, .foot, .foot a { color: #8b8f99; }
  }
  """

  @privacy_html """
  <!doctype html>
  <html lang="ko">
  <head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="index,follow">
  <title>개인정보 처리방침 · sukhi.f3liz.casa</title>
  <style>#{@css}</style>
  </head>
  <body>
  <nav class="nav"><a href="/">← 처음으로</a><a href="/terms">이용약관</a></nav>
  <main class="legal">#{@privacy_body}</main>
  <footer class="foot"><a href="/terms">이용약관</a> · <a href="/">처음으로</a></footer>
  </body>
  </html>
  """

  @terms_html """
  <!doctype html>
  <html lang="ko">
  <head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="index,follow">
  <title>이용약관 · sukhi.f3liz.casa</title>
  <style>#{@css}</style>
  </head>
  <body>
  <nav class="nav"><a href="/">← 처음으로</a><a href="/privacy">개인정보 처리방침</a></nav>
  <main class="legal">#{@terms_body}</main>
  <footer class="foot"><a href="/privacy">개인정보 처리방침</a> · <a href="/">처음으로</a></footer>
  </body>
  </html>
  """

  @spec privacy(Plug.Conn.t()) :: Plug.Conn.t()
  def privacy(conn), do: send_page(conn, @privacy_html)

  @spec terms(Plug.Conn.t()) :: Plug.Conn.t()
  def terms(conn), do: send_page(conn, @terms_html)

  defp send_page(conn, html) do
    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, html)
  end
end
