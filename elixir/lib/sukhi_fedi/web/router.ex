# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.Router do
  use Plug.Router

  alias SukhiFedi.Web.ApiController
  alias SukhiFedi.Web.InboxController
  alias SukhiFedi.Web.WebfingerController
  alias SukhiFedi.Web.ProxyPlug

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # ── ActivityPub / well-known (handled natively by Elixir) ────────────────

  get "/.well-known/webfinger" do
    WebfingerController.call(conn, [])
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

  match _ do
    send_resp(conn, 404, "not found")
  end
end
