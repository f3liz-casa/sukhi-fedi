# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.StreamingSocketTest do
  # Not async: the broadcaster Registry registers under its module name,
  # so a shared global process would clash with a parallel run.
  use ExUnit.Case, async: false

  alias SukhiFedi.Addons.Streaming.Registry
  alias SukhiFedi.Web.StreamingSocket

  setup do
    start_supervised!(Registry)
    :ok
  end

  describe "Registry.broadcast carries the Mastodon stream label" do
    test "local feed is labelled public:local" do
      Registry.subscribe(:local)
      Registry.broadcast(:local, %{event: "update", payload: %{"id" => "1"}})

      assert_receive {:stream_event, "public:local", %{event: "update"}}
    end

    test "home feed is labelled user and is keyed per account" do
      Registry.subscribe(:home, 42)
      Registry.broadcast(:home, %{event: "update", payload: %{"id" => "2"}}, 42)
      assert_receive {:stream_event, "user", %{event: "update"}}

      # an event for a different account must not reach this subscriber
      Registry.broadcast(:home, %{event: "update", payload: %{"id" => "3"}}, 99)
      refute_receive {:stream_event, "user", %{payload: %{"id" => "3"}}}
    end

    test "direct feed is labelled direct and is keyed per account" do
      Registry.subscribe(:direct, 7)
      Registry.broadcast(:direct, %{event: "conversation", payload: %{"id" => "c1"}}, 7)
      assert_receive {:stream_event, "direct", %{event: "conversation"}}

      Registry.broadcast(:direct, %{event: "conversation", payload: %{"id" => "c2"}}, 8)
      refute_receive {:stream_event, "direct", %{payload: %{"id" => "c2"}}}
    end
  end

  describe "init/1" do
    test "subscribes to the initial stream from the query param" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: "public:local"})
      assert MapSet.member?(state.streams, "public:local")
    end

    test "drops the user stream for an app-only token (no account)" do
      {:ok, state} = StreamingSocket.init(%{account_id: nil, initial_stream: "user"})
      refute MapSet.member?(state.streams, "user")
    end

    test "subscribes to the direct stream for a user-bound token" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: "direct"})
      assert MapSet.member?(state.streams, "direct")
    end

    test "drops the direct stream for an app-only token (no account)" do
      {:ok, state} = StreamingSocket.init(%{account_id: nil, initial_stream: "direct"})
      refute MapSet.member?(state.streams, "direct")
    end

    test "without an initial stream, subscribes to nothing" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: nil})
      assert MapSet.size(state.streams) == 0
    end
  end

  describe "handle_info/2 — event delivery" do
    test "pushes a Mastodon frame for a subscribed stream, double-encoding the payload" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: "public:local"})

      event = %{event: "update", payload: %{"id" => "9", "content" => "hi"}}
      assert {:push, {:text, json}, ^state} = StreamingSocket.handle_info({:stream_event, "public:local", event}, state)

      decoded = Jason.decode!(json)
      assert decoded["stream"] == ["public:local"]
      assert decoded["event"] == "update"
      # payload is itself a JSON string, per the Mastodon wire format
      assert is_binary(decoded["payload"])
      assert Jason.decode!(decoded["payload"]) == %{"id" => "9", "content" => "hi"}
    end

    test "ignores events for a stream the socket is not subscribed to" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: "public:local"})
      event = %{event: "update", payload: %{"id" => "9"}}
      assert {:ok, ^state} = StreamingSocket.handle_info({:stream_event, "user", event}, state)
    end

    test "passes a binary payload through untouched (e.g. delete events)" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: "public:local"})
      event = %{event: "delete", payload: "12345"}

      assert {:push, {:text, json}, _} = StreamingSocket.handle_info({:stream_event, "public:local", event}, state)
      assert Jason.decode!(json)["payload"] == "12345"
    end

    test "pushes a conversation frame on the direct stream" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: "direct"})

      event = %{event: "conversation", payload: %{"id" => "42", "unread" => true}}
      assert {:push, {:text, json}, ^state} = StreamingSocket.handle_info({:stream_event, "direct", event}, state)

      decoded = Jason.decode!(json)
      assert decoded["stream"] == ["direct"]
      assert decoded["event"] == "conversation"
      assert Jason.decode!(decoded["payload"]) == %{"id" => "42", "unread" => true}
    end

    test "heartbeat pings the client" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: nil})
      assert {:push, {:ping, ""}, ^state} = StreamingSocket.handle_info(:heartbeat, state)
    end
  end

  describe "handle_in/2 — multiplexed subscribe/unsubscribe" do
    test "subscribe adds a stream, unsubscribe removes it" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: nil})

      {:ok, state} = StreamingSocket.handle_in({~s({"type":"subscribe","stream":"user"}), [opcode: :text]}, state)
      assert MapSet.member?(state.streams, "user")

      {:ok, state} = StreamingSocket.handle_in({~s({"type":"unsubscribe","stream":"user"}), [opcode: :text]}, state)
      refute MapSet.member?(state.streams, "user")
    end

    test "an unknown stream is ignored" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: nil})

      {:ok, new_state} =
        StreamingSocket.handle_in({~s({"type":"subscribe","stream":"hashtag","tag":"x"}), [opcode: :text]}, state)

      assert MapSet.size(new_state.streams) == 0
    end

    test "malformed frames are ignored" do
      {:ok, state} = StreamingSocket.init(%{account_id: 7, initial_stream: nil})
      assert {:ok, ^state} = StreamingSocket.handle_in({"not json", [opcode: :text]}, state)
    end
  end
end
