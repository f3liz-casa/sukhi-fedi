# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.LegalControllerTest do
  use ExUnit.Case, async: true

  # Picked up by the `--only integration` runner; no DB needed.
  @moduletag :integration

  import Plug.Test

  alias SukhiFedi.Web.LegalController

  test "/privacy serves self-contained HTML (no JS, with tables)" do
    conn = conn(:get, "/privacy") |> LegalController.privacy()

    assert conn.status == 200
    assert {"content-type", "text/html; charset=utf-8"} in conn.resp_headers
    assert conn.resp_body =~ "개인정보 처리방침"
    assert conn.resp_body =~ "<table>"
    refute conn.resp_body =~ "<script"
  end

  test "/terms serves self-contained HTML" do
    conn = conn(:get, "/terms") |> LegalController.terms()

    assert conn.status == 200
    assert conn.resp_body =~ "환영합니다"
    refute conn.resp_body =~ "<script"
  end
end
