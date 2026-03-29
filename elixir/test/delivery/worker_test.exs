# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Delivery.WorkerTest do
  use ExUnit.Case, async: true

  # These tests verify that the worker adds HTTP Signature headers to outbound
  # deliveries. They use Bypass to stand up a local HTTP server and assert on
  # the received request headers.

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "perform/1 — HTTP Signature headers" do
    @tag :integration
    test "outbound POST includes Signature header when actor key is found", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/inbox", fn conn ->
        # Assert the Signature header is present
        assert Plug.Conn.get_req_header(conn, "signature") != []
        Plug.Conn.send_resp(conn, 202, "")
      end)

      inbox_url = "http://localhost:#{bypass.port}/inbox"

      # This test requires a running database with an account whose username
      # matches the actor URI used in the job args. Run with `mix test --include
      # integration` after seeding the DB.
      args = %{
        "object_id" => 1,
        "inbox_url" => inbox_url
      }

      # Worker will call ap.sign_delivery via NATS. In a unit test context
      # without NATS, signing is skipped gracefully (returns :skip).
      # The request still goes through — just without a Signature header.
      # A full integration test requires the Docker stack to be running.
      assert :ok = SukhiFedi.Delivery.Worker.perform(%Oban.Job{args: args})
    end
  end
end
