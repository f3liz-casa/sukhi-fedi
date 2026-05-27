# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Router do
  use Plug.Router

  alias SukhiFedi.Web.InboxController
  alias SukhiFedi.Web.WebfingerController
  alias SukhiFedi.Web.NodeinfoController
  alias SukhiFedi.Web.ActorController
  alias SukhiFedi.Web.FeaturedController
  alias SukhiFedi.Web.CollectionController
  alias SukhiFedi.Web.NoteController
  alias SukhiFedi.Web.ViewerController
  alias SukhiFedi.Web.StatsController
  alias SukhiFedi.Web.Auth.LoginController

  plug(Plug.Logger)
  plug(SukhiFedi.Web.AccessLogPlug)
  # Global per-peer rate limit. Conservative ceiling; internal probes
  # like /up from k8s LBs still fit easily. Tighten per-endpoint via
  # dedicated forwarders when needed.
  plug(SukhiFedi.Web.RateLimitPlug, bucket: "global", limit: 500, scale_ms: 60_000)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json, :urlencoded],
    json_decoder: Jason,
    body_reader: {SukhiFedi.Web.CacheBodyReader, :read_body, []}
  )

  plug(:fetch_query_params)

  plug(:dispatch)

  # ── Admin web UI ────────────────────────────────────────────────────────
  # Forward strips the `/admin` prefix; the sub-router owns its own
  # session middleware (cookie-signed via SECRET_KEY_BASE) and runs the
  # Mastodon-OAuth-bearer auth check on every request.
  forward("/admin", to: SukhiFedi.Web.Admin.Router)

  # ── User-facing login (session_token cookie minter) ────────────────────

  get "/login" do
    LoginController.show(conn)
  end

  post "/login" do
    LoginController.submit(conn)
  end

  post "/logout" do
    LoginController.logout(conn)
  end

  # ── Static assets for the SPA + login page ─────────────────────────────
  # The SvelteKit build at `web/build` is copied (or symlinked) into
  # `priv/static`. Cloudflare Pages style deploys can ignore this and
  # serve the SPA from the CDN; this fallback keeps a self-contained
  # one-binary deploy possible.

  get "/static/*path" do
    serve_static(conn, path)
  end

  # ── ActivityPub / well-known (handled natively by Elixir) ────────────────

  get "/.well-known/webfinger" do
    WebfingerController.call(conn, [])
  end

  get "/users/:name" do
    ActorController.show(conn, [])
  end

  get "/users/:name/featured" do
    FeaturedController.show(conn, [])
  end

  get "/users/:name/followers" do
    CollectionController.followers(conn, [])
  end

  get "/users/:name/following" do
    CollectionController.following(conn, [])
  end

  get "/users/:name/outbox" do
    CollectionController.outbox(conn, [])
  end

  get "/users/:name/notes/:note_id" do
    NoteController.show(conn, [])
  end

  post "/users/:name/inbox" do
    InboxController.user_inbox(conn, [])
  end

  post "/inbox" do
    InboxController.shared_inbox(conn, [])
  end

  # ── NodeInfo (Elixir-native) ─────────────────────────────────────────────

  get "/.well-known/nodeinfo" do
    NodeinfoController.discovery(conn, [])
  end

  get "/nodeinfo/2.1" do
    NodeinfoController.v2_1(conn, [])
  end

  # ── Uploaded media ───────────────────────────────────────────────────────
  # Serves files written by `SukhiFedi.Addons.Media.create_from_upload/3`.
  # `MEDIA_DIR` env (default `priv/static/uploads`) controls the on-disk
  # root. Production should front this with a CDN.

  get "/uploads/*path" do
    serve_upload(conn, path)
  end

  # ── Human-facing HTML + JSON proxy for nodeinfo lookup ──────────────────
  # Gated on the :nodeinfo_monitor addon: this is the watcher UI surface
  # (dashboard at /, register/list watchers, host stats SSE). A deployment
  # running sukhi-fedi as a real SNS — not as a watcher app — sets
  # DISABLE_ADDONS=nodeinfo_monitor and these routes go 404.

  get "/" do
    cond do
      nodeinfo_monitor_enabled?() -> ViewerController.home(conn, [])
      true -> serve_spa(conn)
    end
  end

  # SPA-owned client routes. Each one is just the same SvelteKit shell
  # (`priv/static/index.html`); the bundled JS reads the URL and
  # renders the matching page. Listing them explicitly keeps `/api`,
  # `/oauth`, `/.well-known` untouched.

  get "/signup" do
    serve_spa(conn)
  end

  get "/timeline" do
    serve_spa(conn)
  end

  get "/app/callback" do
    serve_spa(conn)
  end

  # PoW で守られる「通り道」。Anubis がこの path だけを challenge する。
  # 中身は SPA shell ─ JS で intent / next を読んで分岐する。
  get "/check" do
    serve_spa(conn)
  end

  # SvelteKit がビルド出力に `_app/` を使うので、こちらも static として
  # 配る(`/static/` と同じ priv/static ルート、prefix だけ別)。
  get "/_app/*path" do
    serve_static(conn, ["_app" | path])
  end

  get "/favicon.ico" do
    serve_static(conn, ["favicon.ico"])
  end

  get "/api/nodeinfo" do
    if nodeinfo_monitor_enabled?(),
      do: ViewerController.nodeinfo_lookup(conn, []),
      else: send_resp(conn, 404, "")
  end

  get "/api/watchers" do
    if nodeinfo_monitor_enabled?(),
      do: ViewerController.list_watchers(conn, []),
      else: send_resp(conn, 404, "")
  end

  post "/api/watchers" do
    if nodeinfo_monitor_enabled?(),
      do: ViewerController.register_watcher(conn, []),
      else: send_resp(conn, 404, "")
  end

  # SSE stream feeding the host-stats card on `/`. One JSON tick per second.
  get "/api/stats/stream" do
    if nodeinfo_monitor_enabled?(),
      do: StatsController.stream(conn, []),
      else: send_resp(conn, 404, "")
  end

  # ── Health + metrics ─────────────────────────────────────────────────────

  get "/up" do
    send_resp(conn, 200, "ok")
  end

  get "/metrics" do
    PromEx.Plug.call(conn, PromEx.Plug.init(prom_ex_module: SukhiFedi.PromEx))
  end

  # ── Mastodon/Misskey REST API — dispatched to plugin nodes ───────────────
  #
  # `SukhiFedi.Web.PluginPlug` forwards the request to one of the plugin
  # Erlang nodes listed in `config :sukhi_fedi, :plugin_nodes`. Each
  # plugin node runs the `:sukhi_api` application (see the top-level
  # `api/` directory) and exposes capabilities via `:rpc`. If no plugin
  # node is reachable the client gets a 503.

  match "/api/v1/*_" do
    SukhiFedi.Web.PluginPlug.call(conn, SukhiFedi.Web.PluginPlug.init([]))
  end

  match "/api/admin/*_" do
    SukhiFedi.Web.PluginPlug.call(conn, SukhiFedi.Web.PluginPlug.init([]))
  end

  # OAuth 2.0 server endpoints (`/oauth/authorize`, `/oauth/token`,
  # `/oauth/revoke`) live on the api plugin node. PluginPlug is
  # path-agnostic so the same forwarder handles them.
  match "/oauth/*_" do
    SukhiFedi.Web.PluginPlug.call(conn, SukhiFedi.Web.PluginPlug.init([]))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp serve_spa(conn) do
    root = Path.join([:code.priv_dir(:sukhi_fedi), "static"])
    index = Path.join(root, "index.html")

    if File.regular?(index) do
      conn
      |> put_resp_content_type("text/html; charset=utf-8")
      |> send_file(200, index)
    else
      send_resp(conn, 404, "frontend not built — run `cd web && npm run build`")
    end
  end

  defp serve_static(conn, path_segments) do
    if Enum.any?(path_segments, &(&1 == "..")) do
      send_resp(conn, 400, "")
    else
      root = Path.join([:code.priv_dir(:sukhi_fedi), "static"])
      relative = Path.join(path_segments)
      full = Path.join(root, relative)

      cond do
        not String.starts_with?(Path.expand(full), Path.expand(root)) ->
          send_resp(conn, 400, "")

        File.regular?(full) ->
          conn
          |> put_resp_content_type(content_type_for(full))
          |> send_file(200, full)

        true ->
          send_resp(conn, 404, "")
      end
    end
  end

  # Path-traversal-safe static serve for `/uploads/<key>`. The key is
  # opaque random bytes generated by the upload pipeline so traversal
  # would only ever return 404, but we reject `..` components defensively.
  defp serve_upload(conn, path_segments) do
    if Enum.any?(path_segments, &(&1 == "..")) do
      send_resp(conn, 400, "")
    else
      root = media_dir()
      relative = Path.join(path_segments)
      full = Path.join(root, relative)

      cond do
        not String.starts_with?(Path.expand(full), Path.expand(root)) ->
          send_resp(conn, 400, "")

        File.regular?(full) ->
          ct = content_type_for(full)

          conn
          |> put_resp_content_type(ct)
          |> send_file(200, full)

        true ->
          send_resp(conn, 404, "")
      end
    end
  end

  defp media_dir do
    System.get_env("MEDIA_DIR") ||
      Path.join([:code.priv_dir(:sukhi_fedi), "static", "uploads"])
  end

  defp content_type_for(path) do
    case Path.extname(path) |> String.downcase() do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".ico" -> "image/x-icon"
      ".mp4" -> "video/mp4"
      ".webm" -> "video/webm"
      ".mp3" -> "audio/mpeg"
      ".ogg" -> "audio/ogg"
      # SvelteKit ビルド成果物。.js は ES module として読まれるので
      # text/javascript が必須(application/octet-stream だと browser
      # が module load を拒否する)。
      ".js" -> "text/javascript"
      ".mjs" -> "text/javascript"
      ".css" -> "text/css"
      ".html" -> "text/html; charset=utf-8"
      ".json" -> "application/json"
      ".map" -> "application/json"
      ".woff" -> "font/woff"
      ".woff2" -> "font/woff2"
      ".ttf" -> "font/ttf"
      _ -> "application/octet-stream"
    end
  end

  # Reads the addon config at request time — set via env vars in
  # config/runtime.exs (ENABLED_ADDONS, DISABLE_ADDONS, ADDON_PRESETS).
  defp nodeinfo_monitor_enabled? do
    enabled = Application.get_env(:sukhi_fedi, :enabled_addons, :all)
    disabled = Application.get_env(:sukhi_fedi, :disabled_addons, [])

    cond do
      :nodeinfo_monitor in disabled -> false
      enabled == :all -> true
      true -> :nodeinfo_monitor in enabled
    end
  end
end
