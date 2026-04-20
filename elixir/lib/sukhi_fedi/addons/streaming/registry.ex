# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.Streaming.Registry do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def subscribe(stream_type, account_id \\ nil) do
    key = stream_key(stream_type, account_id)
    GenServer.call(__MODULE__, {:subscribe, key, self()})
  end

  def unsubscribe(stream_type, account_id \\ nil) do
    key = stream_key(stream_type, account_id)
    GenServer.cast(__MODULE__, {:unsubscribe, key, self()})
  end

  def broadcast(stream_type, event, account_id \\ nil) do
    key = stream_key(stream_type, account_id)
    GenServer.cast(__MODULE__, {:broadcast, key, event})
  end

  defp stream_key(:home, account_id), do: {:home, account_id}
  defp stream_key(:local, _), do: :local

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:subscribe, key, pid}, _from, state) do
    Process.monitor(pid)
    subscribers = Map.get(state, key, MapSet.new())
    {:reply, :ok, Map.put(state, key, MapSet.put(subscribers, pid))}
  end

  @impl true
  def handle_cast({:unsubscribe, key, pid}, state) do
    subscribers = Map.get(state, key, MapSet.new())
    {:noreply, Map.put(state, key, MapSet.delete(subscribers, pid))}
  end

  @impl true
  def handle_cast({:broadcast, key, event}, state) do
    subscribers = Map.get(state, key, MapSet.new())
    Enum.each(subscribers, fn pid -> send(pid, {:stream_event, event}) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    new_state =
      Enum.reduce(state, %{}, fn {key, subscribers}, acc ->
        Map.put(acc, key, MapSet.delete(subscribers, pid))
      end)

    {:noreply, new_state}
  end
end
