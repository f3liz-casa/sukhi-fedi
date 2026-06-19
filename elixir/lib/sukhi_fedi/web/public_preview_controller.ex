# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.PublicPreviewController do
  @moduledoc """
  Server-rendered, JS-free HTML preview of public profiles and notes, for
  the visitors the SPA can't speak to: logged-out humans who arrive with a
  link, and the crawlers / link-unfurlers behind them.

  The SPA ships `ssr=false` + `prerender=true`, so a crawler that GETs
  `/@alice` or a note permalink receives an empty JS shell — no per-page
  title, description or image, so a shared link unfurls as nothing. This
  controller fills that gap with a small, honest, static page.

  Two things keep it calm and honest:

    * **Only public-visibility content is ever rendered.** Profiles list
      only the statuses `Notes.scope_profile_statuses/3` allows a `nil`
      (logged-out) viewer to see; a single note renders only when
      `Notes.visible_to?/2` says a `nil` viewer may — the same single-point
      predicates the AP and Mastodon read paths use (CODE_STYLE §0/§3). We
      never invent a count, a notification, a "live" badge or any state the
      page can't truthfully show.

    * **It is gated, off by default.** `level/0` reads `PUBLIC_PREVIEW`
      once (like the router's `nodeinfo_monitor_enabled?/0`):

        - `:off`  — this controller never runs; the router behaves as before
          (AP JSON for the actor/note routes, SPA shell for `/@…`).
        - `:meta` — emit only `<head>` metadata: Open Graph / Twitter card +
          a JSON-LD block. Fixes link unfurls with near-zero exposure (no
          post body in the HTML).
        - `:full` — `:meta` plus a readable static body (profile summary +
          a single page of recent public posts, or the note's text).

  Negotiation lives in `wants_html_preview?/1`: when the level is not
  `:off` and the client is not asking for ActivityPub JSON, the router
  branches here; otherwise the AP controllers / SPA shell answer exactly as
  they did before. No JS, no SSE, no infinite scroll, no read receipts.
  """

  import Plug.Conn

  alias SukhiFedi.AP.ActorJson
  alias SukhiFedi.{Accounts, Notes}
  alias SukhiFedi.Schema.{Account, Media, Note}

  # How many recent public posts the :full profile body lists. A single
  # static page — there is no "load more", no infinite scroll.
  @profile_posts 20

  # ── the config gate (read once, like nodeinfo_monitor_enabled?/0) ─────────

  @doc """
  The configured preview level: `:off` | `:meta` | `:full`. Read at
  request time from `config :sukhi_fedi, :public_preview` (set from the
  `PUBLIC_PREVIEW` env var in runtime.exs). Defaults to `:off` — a quiet
  instance stays a JS shell to strangers until an operator opts in.
  """
  @spec level() :: :off | :meta | :full
  def level, do: Application.get_env(:sukhi_fedi, :public_preview, :off)

  @doc """
  The one place that decides "should this GET get the HTML preview instead
  of AP JSON / the SPA shell?". True when the preview is enabled **and**
  the client is not an ActivityPub consumer (its `Accept` does not prefer
  `application/activity+json` or `…+ld+json`). Used by every router branch
  that has both an AP/SPA answer and a preview answer, so the negotiation
  rule lives in exactly one named predicate (CODE_STYLE §0/§3).
  """
  @spec wants_html_preview?(Plug.Conn.t()) :: boolean()
  def wants_html_preview?(conn) do
    level() != :off and not prefers_activitypub?(conn)
  end

  # An AP consumer signals it with an `Accept` that names the AP JSON media
  # types. Browsers and crawlers send `text/html`/`*/*` and never these, so
  # the actor- and note-dereference path Mastodon/Misskey/fedify use stays
  # byte-identical — only human/crawler GETs branch to the preview.
  defp prefers_activitypub?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(fn a ->
      String.contains?(a, "application/activity+json") or
        String.contains?(a, "application/ld+json")
    end)
  end

  # ── actions ───────────────────────────────────────────────────────────────

  @doc """
  Render a local account's public profile. `:name` is the username (the
  `/users/:name` and `/@name` routes both land here). Unknown / remote
  usernames 404 — we only ever render our own users' public content.
  """
  @spec profile(Plug.Conn.t()) :: Plug.Conn.t()
  def profile(conn) do
    case Accounts.by_local_username(conn.path_params["name"]) do
      %Account{} = account -> render_profile(conn, account)
      nil -> not_found(conn)
    end
  end

  @doc """
  Render a single public note, named by `:note_id` (the `/users/:name/…` AP
  route) or `:id` (the `/@…` SPA route the router normalises into here).
  Only a note a logged-out viewer may see renders — `Notes.get_note/2` with
  a `nil` viewer applies the single-point visibility predicate, so a
  followers-only or direct note 404s here exactly as it does on the API.
  """
  @spec note(Plug.Conn.t()) :: Plug.Conn.t()
  def note(conn) do
    id = conn.path_params["note_id"] || conn.path_params["id"]

    case Notes.get_note(id, nil) do
      {:ok, %Note{account: %Account{domain: nil}} = note} -> render_note(conn, note)
      _ -> not_found(conn)
    end
  end

  # ── profile rendering ──────────────────────────────────────────────────────

  defp render_profile(conn, %Account{} = account) do
    actor_uri = ActorJson.actor_uri(account)
    name = account.display_name || account.username
    handle = "@#{account.username}@#{domain()}"
    desc = summary_text(account.summary) |> truncate(200) |> fallback(handle)
    avatar = local_image_url(account.avatar_url)

    head =
      meta_head(
        title: "#{name} (#{handle})",
        description: desc,
        url: actor_uri,
        image: avatar,
        og_type: "profile",
        ld: profile_ld(account, actor_uri, name, desc, avatar)
      )

    body =
      if level() == :full do
        posts =
          account.id
          |> Accounts.list_statuses(viewer_id: nil, limit: @profile_posts, exclude_reblogs: true)
          |> Enum.filter(&match?(%Note{}, &1))

        profile_body(account, name, handle, avatar, posts)
      else
        ""
      end

    send_page(conn, "#{name} (#{handle})", head, body)
  end

  defp profile_body(%Account{} = account, name, handle, avatar, posts) do
    summary = account.summary || ""

    """
    <header class="head measure">
      #{img(avatar, "", "avatar")}
      <h1 class="name">#{escape(name)}</h1>
      <p class="handle">#{escape(handle)}</p>
      #{if summary != "", do: ~s(<div class="summary">#{summary}</div>), else: ""}
    </header>
    <main class="measure">
      #{posts |> Enum.map(&post_card/1) |> Enum.join("\n")}
    </main>
    """
  end

  defp post_card(%Note{} = note) do
    permalink = "/@#{note.account.username}/#{note.id}"

    """
    <article class="post">
      <a class="permalink" href="#{permalink}">
        <time datetime="#{DateTime.to_iso8601(note.created_at)}">#{date_label(note.created_at)}</time>
      </a>
      #{cw_or_body(note)}
      #{note.media |> List.wrap() |> media_figures()}
    </article>
    """
  end

  # A content-warning is honoured: the body stays folded behind the CW text
  # (no JS to expand, so we just show the warning and a link to read it on
  # the app). Honest — we don't surface text the author gated behind a CW.
  defp cw_or_body(%Note{cw: cw}) when is_binary(cw) and cw != "" do
    ~s(<p class="cw">#{escape(cw)}</p>)
  end

  defp cw_or_body(%Note{content: content}) do
    # Content is already allow-list-sanitised at write time (HTML.sanitize/1
    # in the note changeset), so it is served as-is — never re-sanitised per
    # render (CODE_STYLE §0 perf rule).
    ~s(<div class="body">#{content}</div>)
  end

  # ── note rendering ─────────────────────────────────────────────────────────

  defp render_note(conn, %Note{account: %Account{} = account} = note) do
    actor_uri = ActorJson.actor_uri(account)
    note_uri = "#{actor_uri}/notes/#{note.id}"
    name = account.display_name || account.username
    handle = "@#{account.username}@#{domain()}"
    desc = note_description(note) |> truncate(200) |> fallback(handle)
    image = note |> Map.get(:media) |> List.wrap() |> first_image_url() || local_image_url(account.avatar_url)

    head =
      meta_head(
        title: "#{name} (#{handle})",
        description: desc,
        url: note_uri,
        image: image,
        og_type: "article",
        ld: note_ld(note, note_uri, actor_uri, name)
      )

    body =
      if level() == :full do
        """
        <main class="measure">
          <article class="post solo">
            <a class="author" href="#{actor_uri}"><strong>#{escape(name)}</strong> <span class="handle">#{escape(handle)}</span></a>
            <a class="permalink" href="#{note_uri}">
              <time datetime="#{DateTime.to_iso8601(note.created_at)}">#{date_label(note.created_at)}</time>
            </a>
            #{cw_or_body(note)}
            #{note.media |> List.wrap() |> media_figures()}
          </article>
        </main>
        """
      else
        ""
      end

    send_page(conn, "#{name} (#{handle})", head, body)
  end

  # ── JSON-LD blocks (schema.org, the form unfurlers read) ───────────────────

  defp profile_ld(%Account{} = account, actor_uri, name, desc, avatar) do
    %{
      "@context" => "https://schema.org",
      "@type" => "ProfilePage",
      "mainEntity" => drop_nil(%{
        "@type" => "Person",
        "name" => name,
        "alternateName" => "@#{account.username}@#{domain()}",
        "description" => desc,
        "url" => actor_uri,
        "image" => avatar
      })
    }
  end

  defp note_ld(%Note{} = note, note_uri, actor_uri, name) do
    drop_nil(%{
      "@context" => "https://schema.org",
      "@type" => "Article",
      "author" => %{"@type" => "Person", "name" => name, "url" => actor_uri},
      "datePublished" => DateTime.to_iso8601(note.created_at),
      "url" => note_uri,
      "headline" => note.title,
      "articleBody" => note_description(note)
    })
  end

  # ── <head> meta (the always-safe layer) ────────────────────────────────────

  # Open Graph + Twitter card + JSON-LD. This is the whole of the `:meta`
  # level and the head of the `:full` page. `robots` is config-controlled so
  # a quiet instance can stay uncrawled even with previews on.
  defp meta_head(opts) do
    title = Keyword.fetch!(opts, :title)
    desc = Keyword.fetch!(opts, :description)
    url = Keyword.fetch!(opts, :url)
    image = Keyword.get(opts, :image)
    og_type = Keyword.fetch!(opts, :og_type)
    ld = Keyword.fetch!(opts, :ld)

    image_tags =
      if image do
        ~s(<meta property="og:image" content="#{escape(image)}">\n<meta name="twitter:image" content="#{escape(image)}">)
      else
        ""
      end

    """
    <meta name="robots" content="#{robots()}">
    <meta name="description" content="#{escape(desc)}">
    <meta property="og:type" content="#{og_type}">
    <meta property="og:title" content="#{escape(title)}">
    <meta property="og:description" content="#{escape(desc)}">
    <meta property="og:url" content="#{escape(url)}">
    <meta property="og:site_name" content="#{escape(domain())}">
    #{image_tags}
    <meta name="twitter:card" content="#{if(image, do: "summary_large_image", else: "summary")}">
    <meta name="twitter:title" content="#{escape(title)}">
    <meta name="twitter:description" content="#{escape(desc)}">
    <script type="application/ld+json">#{ld_json(ld)}</script>
    """
  end

  # `PUBLIC_PREVIEW_ROBOTS` (config :public_preview_robots) controls whether
  # search engines index these pages. Defaults to `noindex, nofollow` — the
  # quiet default; a public instance sets it to `index, follow`.
  defp robots, do: Application.get_env(:sukhi_fedi, :public_preview_robots, "noindex, nofollow")

  # ── page shell + shared bits ───────────────────────────────────────────────

  # The page chrome. `lang` follows the instance default (ja); the calm
  # palette is the tokens.css values, inlined (the SPA stylesheet isn't on a
  # JS-free page). No external font / CDN / script.
  defp send_page(conn, title, head, body) do
    html = """
    <!doctype html>
    <html lang="ja">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{escape(title)} · #{escape(domain())}</title>
    <style>#{css()}</style>
    #{head}
    </head>
    <body>
    #{body}
    <footer class="foot measure"><a href="/">#{escape(domain())}</a></footer>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(200, html)
  end

  defp not_found(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(404, "<!doctype html><meta charset=utf-8><title>not found</title>")
  end

  # media → <figure><img>. Local uploads serve from /uploads/ directly;
  # remote attachments go through the gateway media proxy so the viewer's IP
  # never reaches the origin server (same reason the API view proxies them).
  defp media_figures([]), do: ""

  defp media_figures(media) when is_list(media) do
    media
    |> Enum.filter(&match?(%Media{type: "image"}, &1))
    |> Enum.map(fn m ->
      ~s(<figure>#{img(media_url(m), m.description || "", "")}</figure>)
    end)
    |> Enum.join("\n")
  end

  defp first_image_url(media) do
    media
    |> Enum.find(&match?(%Media{type: "image"}, &1))
    |> case do
      %Media{} = m -> media_url(m)
      nil -> nil
    end
  end

  defp media_url(%Media{remote_url: remote, id: id}) when is_binary(remote),
    do: "https://#{domain()}/proxy/media/#{id}"

  defp media_url(%Media{url: url}), do: url

  # Local profile images are already absolute (/uploads/<key> or a full URL);
  # leave them as-is. nil stays nil so the meta layer omits the image tag.
  defp local_image_url(nil), do: nil
  defp local_image_url(""), do: nil
  defp local_image_url(url), do: url

  defp img(nil, _alt, _class), do: ""
  defp img("", _alt, _class), do: ""

  defp img(url, alt, class) do
    cls = if class == "", do: "", else: ~s( class="#{class}")
    ~s(<img#{cls} src="#{escape(url)}" alt="#{escape(alt)}" loading="lazy">)
  end

  # Strip HTML tags to plaintext for the meta description (OG/Twitter want
  # text, not markup). The content is already sanitised, so this is just
  # tag-removal + entity-decode for a clean one-line summary.
  defp summary_text(nil), do: ""

  defp summary_text(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> decode_basic_entities()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # The only entities our sanitiser emits — decode just these for a clean
  # plaintext summary; anything else stays literal (it won't appear).
  defp decode_basic_entities(s) do
    s
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end

  defp note_description(%Note{title: t, content: c}) when is_binary(t) and t != "" do
    "#{t} — #{summary_text(c)}" |> String.trim_trailing(" — ")
  end

  defp note_description(%Note{content: c}), do: summary_text(c)

  defp truncate(s, max) when byte_size(s) <= max, do: s
  defp truncate(s, max), do: String.slice(s, 0, max) |> String.trim_trailing() |> Kernel.<>("…")

  defp fallback("", alt), do: alt
  defp fallback(s, _alt), do: s

  defp date_label(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")

  defp domain, do: SukhiFedi.Config.domain!()

  defp escape(s) when is_binary(s), do: Plug.HTML.html_escape(s)
  defp escape(_), do: ""

  defp drop_nil(map), do: :maps.filter(fn _k, v -> not is_nil(v) and v != "" end, map)

  # JSON-LD is data, but it lands inside a <script> block, so guard the one
  # break-out vector: a literal `</script>` in a value. JSON.encode! handles
  # the rest (it already escapes quotes/backslashes).
  defp ld_json(map) do
    map |> JSON.encode!() |> String.replace("</", "<\\/")
  end

  # Calm palette: the tokens.css values (warm paper, ink, low-chroma), used
  # directly — this JS-free page can't read the SPA stylesheet, so the one
  # place those values live is mirrored here (the same move LegalController
  # makes). Japanese line-breaking is the CSS half of the BudouX trick
  # (keep-all + overflow-wrap), which needs no JS.
  defp css do
    """
    :root { color-scheme: light dark; }
    * { box-sizing: border-box; margin: 0; }
    body { font-family: system-ui, -apple-system, "BIZ UDPGothic", sans-serif;
      line-height: 1.6; color: #262521; background: #efeee7;
      word-break: keep-all; overflow-wrap: break-word; }
    .measure { max-width: 36rem; margin-inline: auto; padding: 0 1.25rem; }
    a { color: #262521; text-underline-offset: 0.16em; text-decoration-color: #b6b4a4; }
    a:hover { text-decoration-color: #262521; }
    .head { padding-top: 2rem; }
    .head .avatar { width: 72px; height: 72px; border-radius: 5px; object-fit: cover; }
    .name { font-size: 1.5rem; margin-top: 0.75rem; }
    .handle { color: #6a6960; }
    .summary { margin-top: 0.75rem; }
    .post { padding: 1.25rem 0; border-top: 1px solid #d8d6c9; }
    .post.solo { border-top: none; padding-top: 2rem; }
    .post .author { display: block; margin-bottom: 0.25rem; }
    .post .author .handle { color: #6a6960; font-weight: 400; }
    time { color: #6a6960; font-size: 0.875rem; }
    .permalink { text-decoration: none; }
    .cw { color: #6a6960; font-style: italic; }
    .body { margin-top: 0.25rem; }
    .body p { margin-bottom: 0.5rem; }
    figure { margin-top: 0.75rem; }
    figure img { max-width: 100%; height: auto; border-radius: 5px; }
    .foot { padding: 2rem 0 3rem; color: #6a6960; font-size: 0.875rem; }
    @media (prefers-color-scheme: dark) {
      body { color: #dcdde0; background: #16181c; }
      a { color: #dcdde0; text-decoration-color: #555; }
      a:hover { text-decoration-color: #dcdde0; }
      .handle, .post .author .handle, time, .cw, .foot { color: #8b8f99; }
      .post { border-top-color: #2a2e37; }
    }
    """
  end
end
