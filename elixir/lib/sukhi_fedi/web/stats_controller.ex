# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.StatsController do
  @moduledoc """
  Server-Sent Events stream of host-OS CPU, memory, and load average for
  the main viewer page. One JSON sample per second.

  Numbers come from `SukhiFedi.SystemMetrics` (the single host-metrics
  home, backed by `:os_mon`). Disk is intentionally left out of this
  stream — the viewer card shows only CPU/memory/load — but the same
  source feeds the richer `/admin/system` page.
  """

  import Plug.Conn

  alias SukhiFedi.SystemMetrics

  @tick_ms 1_000

  def stream(conn, _opts) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      # Proxies (nginx) often buffer text/event-stream; opt out explicitly.
      |> put_resp_header("x-accel-buffering", "no")
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)

    # Prime cpu_sup so the first sample covers our tick interval rather
    # than an unbounded "since boot" window.
    _ = SystemMetrics.cpu_util()
    tick(conn)
  end

  defp tick(conn) do
    Process.sleep(@tick_ms)

    payload =
      JSON.encode!(%{
        cpu: SystemMetrics.cpu_util(),
        memory: SystemMetrics.memory(),
        load: SystemMetrics.load_avg(),
        ts: System.system_time(:second)
      })

    case chunk(conn, "data: #{payload}\n\n") do
      {:ok, conn} -> tick(conn)
      {:error, _reason} -> conn
    end
  end
end
