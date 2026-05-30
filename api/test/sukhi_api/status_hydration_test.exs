# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.StatusHydrationTest do
  use ExUnit.Case, async: false

  alias SukhiApi.StatusHydration

  # Returns reaction chips for any note, so we can assert they land in the
  # rendered status. Anything else is "no gateway".
  defmodule FakeRpc do
    def call(mod, fun, args), do: call(mod, fun, args, 5_000)

    def call(SukhiFedi.Notes, :reactions_for_notes, [note_ids, _viewer_id], _t) do
      {:ok, Map.new(note_ids, fn id -> {id, [%{name: "🦊", count: 2, me: false}]} end)}
    end

    def call(_, _, _, _), do: {:error, :not_connected}
  end

  defmodule DisconnectedRpc do
    def call(mod, fun, args), do: call(mod, fun, args, 5_000)
    def call(_, _, _, _), do: {:error, :not_connected}
  end

  setup do
    prev = Application.get_env(:sukhi_api, :gateway_rpc_impl)
    Application.put_env(:sukhi_api, :gateway_rpc_impl, FakeRpc)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:sukhi_api, :gateway_rpc_impl, prev),
        else: Application.delete_env(:sukhi_api, :gateway_rpc_impl)
    end)

    :ok
  end

  defp note(id) do
    %{
      id: id,
      content: "n#{id}",
      visibility: "public",
      ap_id: "https://x.example/notes/#{id}",
      cw: nil,
      created_at: ~U[2026-04-21 00:00:00Z],
      account: %{id: 1, username: "alice", display_name: "A", summary: "", is_bot: false},
      media: []
    }
  end

  test "many/2 attaches reaction chips from the gateway" do
    assert [rendered] = StatusHydration.many([note(7)], %{id: 1})
    assert [%{name: "🦊", count: 2}] = rendered.reactions
  end

  test "one/2 attaches reactions to a single note" do
    rendered = StatusHydration.one(note(9), %{id: 1})
    assert [%{name: "🦊"}] = rendered.reactions
  end

  test "one/2 returns nil for a nil note" do
    assert StatusHydration.one(nil, %{id: 1}) == nil
  end

  test "many/2 on an empty list does no RPC and returns []" do
    assert StatusHydration.many([], %{id: 1}) == []
  end

  test "a disconnected gateway yields empty reactions, not a crash" do
    Application.put_env(:sukhi_api, :gateway_rpc_impl, DisconnectedRpc)
    assert [rendered] = StatusHydration.many([note(1)], nil)
    assert rendered.reactions == []
  end
end
