# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Outbox.RelayTest do
  use ExUnit.Case, async: true

  alias SukhiDelivery.Outbox.Relay
  alias SukhiDelivery.Schema.OutboxEvent

  defp ev(id), do: %OutboxEvent{id: id}

  describe "tally/1 — folding publish outcomes" do
    test "collects published ids and keeps poison for the caller to count" do
      outcomes = [
        {ev(1), :ok},
        {ev(2), {:poison, {:encode, "bad"}}},
        {ev(3), :ok}
      ]

      assert {published, poison} = Relay.tally(outcomes)
      assert Enum.sort(published) == [1, 3]
      assert [{%OutboxEvent{id: 2}, {:encode, "bad"}}] = poison
    end

    test "halts at the first :disconnected — nothing after it is touched" do
      outcomes = [
        {ev(1), :ok},
        {ev(2), {:disconnected, :not_connected}},
        {ev(3), :ok},
        {ev(4), {:poison, :x}}
      ]

      # Only 1 made it out; 2,3,4 stay pending (no poison row, no publish),
      # so a NATS outage never burns the per-event `attempts` budget.
      assert {[1], []} = Relay.tally(outcomes)
    end

    test "a disconnect on the very first event defers the whole batch" do
      outcomes = [
        {ev(1), {:disconnected, :not_connected}},
        {ev(2), :ok}
      ]

      assert {[], []} = Relay.tally(outcomes)
    end

    test "lazy over a stream: the :halt stops further publish attempts" do
      pulled = :counters.new(1, [])

      outcomes =
        Stream.map(1..10, fn n ->
          :counters.add(pulled, 1, 1)
          if n == 3, do: {ev(n), {:disconnected, :down}}, else: {ev(n), :ok}
        end)

      assert {published, []} = Relay.tally(outcomes)
      assert Enum.sort(published) == [1, 2]
      # Pulled exactly up to and including the disconnect; 4..10 never run.
      assert :counters.get(pulled, 1) == 3
    end
  end
end
