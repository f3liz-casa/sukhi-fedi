# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.SystemMetrics do
  @moduledoc """
  Host-OS resource snapshot — CPU utilisation, system memory, load
  average, and disk usage — plus the BEAM's own memory footprint.

  The single home for "how loaded is this box". Backed by `:os_mon`
  (`:cpu_sup` / `:memsup` / `:disksup`), which on Linux reads `/proc`
  and `statvfs`. Both the public NodeInfo viewer's stats stream
  (`SukhiFedi.Web.StatsController`) and the `/admin/system` page read
  through here so the two never describe the box differently.

  `:cpu_sup.util/0` reports utilisation *since the previous call*, so
  the first reading after a quiet period covers a long window — prime it
  once (call and discard) before sampling on an interval.

  Note for containers: these are host-OS figures from the kernel, not
  cgroup limits, so on a shared box they describe the whole machine.
  """

  @doc "One full host snapshot: cpu, memory, load, disk, beam."
  def snapshot do
    %{
      cpu: cpu_util(),
      memory: memory(),
      load: load_avg(),
      disk: disk(),
      beam: beam_memory()
    }
  end

  @doc "CPU utilisation percent since the previous call (0.0 on error)."
  def cpu_util do
    case :cpu_sup.util() do
      n when is_number(n) -> n * 1.0
      _ -> 0.0
    end
  end

  @doc "System memory in bytes: total / used / available, swap, and the rest."
  def memory do
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

  @doc "Load averages over 1 / 5 / 15 minutes (nil per slot on error)."
  def load_avg do
    %{"1m" => load(:avg1), "5m" => load(:avg5), "15m" => load(:avg15)}
  end

  defp load(fun) do
    case apply(:cpu_sup, fun, []) do
      n when is_integer(n) -> n / 256
      _ -> nil
    end
  end

  @doc """
  Disk usage per mounted filesystem (sizes in bytes).

  `:disksup.get_disk_data/0` yields `{mount_charlist, total_kb,
  percent_used}`; the placeholder `{~c"none", 0, 0}` shows before the
  first scan finishes, so drop it. disksup rescans on a timer
  (`:disk_space_check_interval`), so these refresh slower than CPU/mem.
  """
  def disk do
    :disksup.get_disk_data()
    |> Enum.reject(fn {id, total, _pct} -> id == ~c"none" or total == 0 end)
    |> Enum.map(fn {id, total_kb, percent} ->
      %{mount: to_string(id), total: total_kb * 1024, used_percent: percent}
    end)
  end

  @doc "The BEAM VM's own memory footprint in bytes — i.e. sukhi-fedi itself."
  def beam_memory do
    %{
      total: :erlang.memory(:total),
      processes: :erlang.memory(:processes),
      binary: :erlang.memory(:binary)
    }
  end
end
