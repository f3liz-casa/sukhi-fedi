# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Web.ApiControllerTest do
  use ExUnit.Case, async: true
  import Mox

  # Define a mock for the AP.Client so tests don't need a live NATS connection.
  # Add `Mox.defmock(SukhiFedi.AP.MockClient, for: SukhiFedi.AP.ClientBehaviour)` to
  # test_helper.exs once a ClientBehaviour module is defined.

  describe "create_note/2 — missing params" do
    test "returns 400 when 'token' is absent" do
      # Build a minimal Plug.Conn with an empty body_params
      conn =
        Plug.Test.conn(:post, "/api/notes", %{"content" => "hello"})
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [:json], json_decoder: Jason)
        )

      # Expect a 400 because "token" is missing. Since the controller calls
      # Client.request/2 only after the guard passes, a missing token means we
      # never even reach the NATS call — no mock setup needed.
      conn = SukhiFedi.Web.ApiController.create_note(conn, [])
      assert conn.status == 400
      assert %{"error" => "missing required fields"} = Jason.decode!(conn.resp_body)
    end

    test "returns 400 when 'content' is absent" do
      conn =
        Plug.Test.conn(:post, "/api/notes", %{"token" => "abc"})
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [:json], json_decoder: Jason)
        )

      conn = SukhiFedi.Web.ApiController.create_note(conn, [])
      assert conn.status == 400
      assert %{"error" => "missing required fields"} = Jason.decode!(conn.resp_body)
    end
  end

  describe "create_boost/2 — missing params" do
    test "returns 400 when 'object' is absent" do
      conn =
        Plug.Test.conn(:post, "/api/boosts", %{"token" => "abc"})
        |> Plug.Parsers.call(
          Plug.Parsers.init(parsers: [:json], json_decoder: Jason)
        )

      conn = SukhiFedi.Web.ApiController.create_boost(conn, [])
      assert conn.status == 400
    end
  end
end
