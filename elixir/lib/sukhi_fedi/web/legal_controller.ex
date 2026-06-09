# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.LegalController do
  @moduledoc """
  Serves the static legal pages — terms of service and privacy policy — in
  Japanese (default) and Korean.

  Robust by construction: the Markdown sources in `priv/legal/` are rendered
  to HTML **at compile time** and baked into the release. At runtime we only
  pick a baked body and concatenate a tiny chrome — no Markdown parsing, no
  JS, no database, no SPA — so the pages render even if everything else is
  down. A malformed source fails the build instead of reaching production.
  Fully self-contained (inline CSS, no external fonts/CDN).

  Languages: the Japanese privacy policy follows Japan's APPI; the Korean
  follows PIPA. `?lang=ko` switches to Korean; default is Japanese (the
  instance's default UI language). Update by editing `priv/legal/*.md` and
  rebuilding.
  """
  import Plug.Conn

  @ja_privacy Path.expand("../../../priv/legal/privacy.ja.md", __DIR__)
  @ko_privacy Path.expand("../../../priv/legal/privacy.ko.md", __DIR__)
  @ja_terms Path.expand("../../../priv/legal/terms.ja.md", __DIR__)
  @ko_terms Path.expand("../../../priv/legal/terms.ko.md", __DIR__)

  @external_resource @ja_privacy
  @external_resource @ko_privacy
  @external_resource @ja_terms
  @external_resource @ko_terms

  @opts %Earmark.Options{gfm: true, breaks: false}
  @privacy_ja Earmark.as_html!(File.read!(@ja_privacy), @opts)
  @privacy_ko Earmark.as_html!(File.read!(@ko_privacy), @opts)
  @terms_ja Earmark.as_html!(File.read!(@ja_terms), @opts)
  @terms_ko Earmark.as_html!(File.read!(@ko_terms), @opts)

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
  .legal a { color: #2563eb; text-underline-offset: 2px; word-break: break-word; }
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
  .foot a { color: #666; margin-right: .6rem; }
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

  @spec privacy(Plug.Conn.t()) :: Plug.Conn.t()
  def privacy(conn) do
    case lang(conn) do
      "ko" ->
        render(conn, "ko", "개인정보 처리방침", @privacy_ko, "/privacy", {"이용약관", "/terms?lang=ko"})

      _ ->
        render(conn, "ja", "個人情報の取り扱いについて", @privacy_ja, "/privacy", {"利用規約", "/terms"})
    end
  end

  @spec terms(Plug.Conn.t()) :: Plug.Conn.t()
  def terms(conn) do
    case lang(conn) do
      "ko" ->
        render(conn, "ko", "이용약관", @terms_ko, "/terms", {"개인정보 처리방침", "/privacy?lang=ko"})

      _ ->
        render(conn, "ja", "利用規約", @terms_ja, "/terms", {"プライバシーポリシー", "/privacy"})
    end
  end

  defp lang(conn) do
    case conn.query_params do
      %{"lang" => "ko"} -> "ko"
      _ -> "ja"
    end
  end

  # Build the self-contained page at runtime: pick the baked body, wrap a
  # tiny chrome (home, the other doc in the same language, a language
  # toggle). Pure string work — cannot fail.
  defp render(conn, lang, title, body, self_path, {cross_label, cross_href}) do
    {home, toggle_label, toggle_href} =
      if lang == "ko",
        do: {"처음으로", "日本語", self_path},
        else: {"トップへ", "한국어", self_path <> "?lang=ko"}

    html = """
    <!doctype html>
    <html lang="#{lang}">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="index,follow">
    <title>#{title} · sukhi.f3liz.casa</title>
    <style>#{@css}</style>
    </head>
    <body>
    <nav class="nav"><a href="/">← #{home}</a><a href="#{cross_href}">#{cross_label}</a><a href="#{toggle_href}">#{toggle_label}</a></nav>
    <main class="legal">#{body}</main>
    <footer class="foot"><a href="#{cross_href}">#{cross_label}</a><a href="#{toggle_href}">#{toggle_label}</a><a href="/">#{home}</a></footer>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, html)
  end
end
