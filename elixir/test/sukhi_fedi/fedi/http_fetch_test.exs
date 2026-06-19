# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Fedi.HttpFetchTest do
  use ExUnit.Case, async: true

  alias SukhiFedi.Fedi.HttpFetch

  # A loopback server we control: one route streams more than the 1 MiB
  # cap, the other a tiny JSON document. No network, no DB. capped_get/2
  # does not do the SSRF guard (that is the caller's boundary), so hitting
  # 127.0.0.1 here is fine — the test is only about the body cap.
  defmodule Server do
    import Plug.Conn

    def init(opts), do: opts

    def call(%Plug.Conn{path_info: ["huge"]} = conn, _opts) do
      # 2 MiB — past HttpFetch's 1 MiB cap.
      conn
      |> put_resp_content_type("application/activity+json")
      |> send_resp(200, :binary.copy("x", 2 * 1024 * 1024))
    end

    def call(%Plug.Conn{path_info: ["tiny"]} = conn, _opts) do
      conn
      |> put_resp_content_type("application/activity+json")
      |> send_resp(200, ~s({"id":"https://example.test/1"}))
    end
  end

  setup do
    # Unique names so the two async tests don't collide on a shared Finch.
    finch_name = Module.concat(__MODULE__, "Finch#{System.unique_integer([:positive])}")
    {:ok, finch} = Finch.start_link(name: finch_name)
    {:ok, server} = Bandit.start_link(plug: Server, scheme: :http, port: 0, ip: {127, 0, 0, 1})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    on_exit(fn ->
      Process.exit(server, :normal)
      Process.exit(finch, :normal)
    end)

    %{base: "http://127.0.0.1:#{port}", finch: finch_name}
  end

  test "an over-limit response body yields {:error, :document_too_large}", %{
    base: base,
    finch: finch
  } do
    assert {:error, :document_too_large} =
             HttpFetch.capped_get("#{base}/huge", finch: finch, retry: false)
  end

  test "a small response body passes through as the raw binary", %{base: base, finch: finch} do
    assert {:ok, %Req.Response{status: 200, body: body}} =
             HttpFetch.capped_get("#{base}/tiny", finch: finch, retry: false)

    # into: streams raw bytes; Req does not auto-decode under the collector.
    assert body == ~s({"id":"https://example.test/1"})
  end
end
