# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.CorsPlugTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias SukhiFedi.Web.CorsPlug

  describe "preflight (OPTIONS)" do
    test "answers 204, halts, and echoes the requested headers" do
      conn =
        conn(:options, "/api/v1/accounts/verify_credentials")
        |> put_req_header("origin", "https://main.elk.zone")
        |> put_req_header("access-control-request-method", "GET")
        |> put_req_header("access-control-request-headers", "authorization")
        |> CorsPlug.call(CorsPlug.init([]))

      assert conn.status == 204
      assert conn.halted
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert get_resp_header(conn, "access-control-allow-methods") != []
      assert get_resp_header(conn, "access-control-allow-headers") == ["authorization"]
      assert get_resp_header(conn, "access-control-max-age") == ["86400"]
    end

    test "falls back to a default allow-headers list when none requested" do
      conn =
        conn(:options, "/api/v1/timelines/home")
        |> CorsPlug.call(CorsPlug.init([]))

      assert conn.status == 204
      assert [hdrs] = get_resp_header(conn, "access-control-allow-headers")
      assert hdrs =~ "authorization"
    end
  end

  describe "actual requests" do
    test "attach allow-origin + expose-headers to the sent response" do
      conn =
        conn(:get, "/api/v1/accounts/verify_credentials")
        |> CorsPlug.call(CorsPlug.init([]))
        |> send_resp(200, "ok")

      refute conn.halted
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert [expose] = get_resp_header(conn, "access-control-expose-headers")
      assert expose =~ "link"
    end
  end
end
