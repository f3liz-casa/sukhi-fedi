# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Router do
  use Plug.Router

  alias SukhiFedi.Web.InboxController
  alias SukhiFedi.Web.WebfingerController
  alias SukhiFedi.Web.NodeinfoController
  alias SukhiFedi.Web.ActorController
  alias SukhiFedi.Web.FeaturedController
  alias SukhiFedi.Web.CollectionController

  plug(Plug.Logger)
  # Global per-peer rate limit. Conservative ceiling; internal probes
  # like /up from k8s LBs still fit easily. Tighten per-endpoint via
  # dedicated forwarders when needed.
  plug(SukhiFedi.Web.RateLimitPlug, bucket: "global", limit: 500, scale_ms: 60_000)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

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

  match _ do
    send_resp(conn, 404, "not found")
  end
end
