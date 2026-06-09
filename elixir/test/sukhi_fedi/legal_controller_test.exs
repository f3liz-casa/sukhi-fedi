# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.LegalControllerTest do
  use ExUnit.Case, async: true

  # Picked up by the `--only integration` runner; no DB needed.
  @moduletag :integration

  import Plug.Test

  alias SukhiFedi.Web.LegalController

  defp get(path), do: conn(:get, path) |> Plug.Conn.fetch_query_params()

  test "/privacy defaults to Japanese (APPI), self-contained HTML, no JS" do
    conn = get("/privacy") |> LegalController.privacy()

    assert conn.status == 200
    assert {"content-type", "text/html; charset=utf-8"} in conn.resp_headers
    assert conn.resp_body =~ "個人情報の取り扱いについて"
    assert conn.resp_body =~ "個人情報保護法"
    assert conn.resp_body =~ "<table>"
    refute conn.resp_body =~ "<script"
  end

  test "Japanese page embeds BIZ UDPGothic, Korean embeds Nanum, no external font request" do
    ja = get("/privacy") |> LegalController.privacy() |> Map.get(:resp_body)
    ko = get("/privacy?lang=ko") |> LegalController.privacy() |> Map.get(:resp_body)

    # ja page: BIZ font embedded, Nanum not present
    assert ja =~ ~s("BIZ UDPGothic")
    assert ja =~ "@font-face"
    assert ja =~ "font/woff2;base64,"
    refute ja =~ "Nanum"

    # ko page: Nanum embedded, BIZ not present
    assert ko =~ ~s("Nanum Gothic")
    refute ko =~ "BIZ UDPGothic"

    # never an external font request (privacy page must not call Google)
    refute ja =~ "googleapis"
    refute ja =~ "gstatic"
    refute ko =~ "gstatic"
  end

  test "/privacy?lang=ko serves the Korean (PIPA) version" do
    conn = get("/privacy?lang=ko") |> LegalController.privacy()

    assert conn.status == 200
    assert conn.resp_body =~ "개인정보 처리방침"
    refute conn.resp_body =~ "<script"
  end

  test "/terms defaults to Japanese and links to the privacy page" do
    conn = get("/terms") |> LegalController.terms()

    assert conn.status == 200
    assert conn.resp_body =~ "ようこそ"
    assert conn.resp_body =~ ~s(href="/privacy")
    refute conn.resp_body =~ "<script"
  end

  test "/terms?lang=ko serves the Korean version" do
    conn = get("/terms?lang=ko") |> LegalController.terms()

    assert conn.status == 200
    assert conn.resp_body =~ "환영합니다"
  end
end
