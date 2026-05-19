# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Cache.Ets do
  @moduledoc """
  ETS wrapper with TTL sweep. Tables used by the delivery node's
  outbound resolution (remote actor cache today; room for more).
  """

  use GenServer

  @tables [:actor_remote]
  @sweep_interval_ms 60_000

  @spec get(atom(), term()) :: {:ok, term()} | :miss
  def get(table, key) do
    now = System.system_time(:second)

    case :ets.lookup(table, key) do
      [{^key, value, expiry}] when expiry > now -> {:ok, value}
      _ -> :miss
    end
  end

  @spec put(atom(), term(), term(), non_neg_integer()) :: true
  def put(table, key, value, ttl_seconds) do
    expiry = System.system_time(:second) + ttl_seconds
    :ets.insert(table, {key, value, expiry})
  end

  @spec delete(atom(), term()) :: true
  def delete(table, key), do: :ets.delete(table, key)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    Enum.each(@tables, fn t ->
      :ets.new(t, [:named_table, :public, read_concurrency: true])
    end)

    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:second)

    Enum.each(@tables, fn t ->
      :ets.select_delete(t, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    end)

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)
end
