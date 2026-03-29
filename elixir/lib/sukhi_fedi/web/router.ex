# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.Router do
  use Plug.Router

  alias SukhiFedi.Web.ApiController
  alias SukhiFedi.Web.InboxController
  alias SukhiFedi.Web.WebfingerController
  alias SukhiFedi.Web.ProxyPlug
  alias SukhiFedi.Web.ActorController
  alias SukhiFedi.Web.FeaturedController
  alias SukhiFedi.Web.CollectionController

  plug(Teleplug)
  plug(Plug.Logger)
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

  # ── REST API v1 + admin — proxied to Deno ────────────────────────────────
  #
  # Deno's Hono server handles auth, business logic, and NATS RPC.
  # For streaming endpoints Deno responds with X-Delegate-To: Streaming
  # and ProxyPlug hands the socket to StreamingController instead of
  # forwarding the response.

  match "/api/v1/*_" do
    ProxyPlug.call(conn, [])
  end

  match "/api/admin/*_" do
    ProxyPlug.call(conn, [])
  end

  get "/up" do
    send_resp(conn, 200, "ok")
  end

  get "/metrics" do
    PromEx.Plug.call(conn, PromEx.Plug.init(prom_ex_module: SukhiFedi.PromEx))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
