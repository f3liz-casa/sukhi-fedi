# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.Router do
  use Plug.Router

  alias SukhiFedi.Web.ApiController
  alias SukhiFedi.Web.InboxController
  alias SukhiFedi.Web.WebfingerController

  plug Plug.Logger
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  get "/.well-known/webfinger" do
    WebfingerController.call(conn, [])
  end

  post "/users/:name/inbox" do
    InboxController.user_inbox(conn, [])
  end

  post "/inbox" do
    InboxController.shared_inbox(conn, [])
  end

  post "/api/accounts" do
    ApiController.create_account(conn, [])
  end
  post "/api/tokens" do
    ApiController.create_token(conn, [])
  end
  post "/api/notes" do
    ApiController.create_note(conn, [])
  end

  post "/api/notes/cw" do
    ApiController.create_note_cw(conn, [])
  end

  post "/api/boosts" do
    ApiController.create_boost(conn, [])
  end

  post "/api/reacts" do
    ApiController.create_react(conn, [])
  end

  post "/api/quotes" do
    ApiController.create_quote(conn, [])
  end

  post "/api/polls" do
    ApiController.create_poll(conn, [])
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
