# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.StatsController do
  @moduledoc """
  Server-Sent Events stream of host-OS CPU, memory, and load average for
  the main viewer page. One JSON sample per second.

  Data source: `:os_mon` — `:cpu_sup.util/0` (% since last call) and
  `:memsup.get_system_memory_data/0` (`/proc/meminfo` on Linux).
  """

  import Plug.Conn

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
    _ = cpu_util()
    tick(conn)
  end

  defp tick(conn) do
    Process.sleep(@tick_ms)

    payload =
      Jason.encode!(%{
        cpu: cpu_util(),
        memory: memory_snapshot(),
        load: load_avg(),
        ts: System.system_time(:second)
      })

    case chunk(conn, "data: #{payload}\n\n") do
      {:ok, conn} -> tick(conn)
      {:error, _reason} -> conn
    end
  end

  defp cpu_util do
    case :cpu_sup.util() do
      n when is_number(n) -> n * 1.0
      _ -> 0.0
    end
  end

  defp memory_snapshot do
    data = :memsup.get_system_memory_data() |> Enum.into(%{})
    total = Map.get(data, :system_total_memory, 0)
    available = Map.get(data, :available_memory) || Map.get(data, :free_memory, 0)
    used = max(total - available, 0)

    %{
      total: total,
      used: used,
      available: available,
      free: Map.get(data, :free_memory, 0),
      buffered: Map.get(data, :buffered_memory, 0),
      cached: Map.get(data, :cached_memory, 0),
      swap_total: Map.get(data, :total_swap, 0),
      swap_free: Map.get(data, :free_swap, 0)
    }
  end

  defp load_avg do
    %{"1m" => load(:avg1), "5m" => load(:avg5), "15m" => load(:avg15)}
  end

  defp load(fun) do
    case apply(:cpu_sup, fun, []) do
      n when is_integer(n) -> n / 256
      _ -> nil
    end
  end
end
