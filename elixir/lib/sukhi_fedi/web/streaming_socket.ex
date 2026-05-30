# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Web.StreamingSocket do
  @moduledoc """
  WebSock handler for `/api/v1/streaming` — the Mastodon streaming API.

  One process per client connection. It subscribes to the feeds the
  client asks for through `SukhiFedi.Addons.Streaming.Registry` and
  forwards each broadcast as a Mastodon-shaped text frame:

      {"stream":["user"],"event":"update","payload":"<status JSON string>"}

  Only the streams the broadcaster actually fans out are supported:

    * `user`         — the authenticated account's home timeline
    * `public:local` — the local public timeline
    * `direct`       — the authenticated account's DM conversations

  A client either names one stream up front via `?stream=` or multiplexes
  over a single socket with `{"type":"subscribe","stream":"..."}` /
  `{"type":"unsubscribe","stream":"..."}` text frames.

  A ping every 30s keeps idle proxies and Bandit's idle-timeout from
  dropping a quiet-but-live connection; the client's automatic pong
  resets the clock. The Registry monitors this pid, so a disconnect
  cleans up the subscriptions on its own — no explicit teardown needed.
  """

  @behaviour WebSock

  alias SukhiFedi.Addons.Streaming.Registry

  @heartbeat_ms 30_000

  @impl true
  def init(state) do
    schedule_heartbeat()
    state = Map.put(state, :streams, MapSet.new())

    case Map.get(state, :initial_stream) do
      stream when is_binary(stream) -> {:ok, subscribe(state, stream)}
      _ -> {:ok, state}
    end
  end

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, %{"type" => "subscribe", "stream" => stream}} ->
        {:ok, subscribe(state, stream)}

      {:ok, %{"type" => "unsubscribe", "stream" => stream}} ->
        {:ok, unsubscribe(state, stream)}

      _ ->
        {:ok, state}
    end
  end

  def handle_in(_frame, state), do: {:ok, state}

  @impl true
  def handle_info({:stream_event, label, event}, state) do
    if MapSet.member?(state.streams, label) do
      {:push, {:text, frame(label, event)}, state}
    else
      {:ok, state}
    end
  end

  def handle_info(:heartbeat, state) do
    schedule_heartbeat()
    {:push, {:ping, ""}, state}
  end

  def handle_info(_msg, state), do: {:ok, state}

  # ── internals ──────────────────────────────────────────────────────────

  defp subscribe(state, stream) do
    case stream_spec(stream, state.account_id) do
      {type, account_id, label} ->
        Registry.subscribe(type, account_id)
        %{state | streams: MapSet.put(state.streams, label)}

      :ignore ->
        state
    end
  end

  defp unsubscribe(state, stream) do
    case stream_spec(stream, state.account_id) do
      {type, account_id, label} ->
        Registry.unsubscribe(type, account_id)
        %{state | streams: MapSet.delete(state.streams, label)}

      :ignore ->
        state
    end
  end

  # `{registry_stream_type, account_id, mastodon_label}`. The home feed
  # needs an account to key on, so `user` is dropped for app-only tokens.
  defp stream_spec("user", account_id) when is_integer(account_id),
    do: {:home, account_id, "user"}

  defp stream_spec("public:local", _account_id), do: {:local, nil, "public:local"}

  defp stream_spec("direct", account_id) when is_integer(account_id),
    do: {:direct, account_id, "direct"}

  defp stream_spec(_other, _account_id), do: :ignore

  defp frame(label, %{event: event, payload: payload}) do
    Jason.encode!(%{stream: [label], event: event, payload: encode_payload(payload)})
  end

  # Mastodon double-encodes the payload: the status/notification is itself
  # a JSON string inside the frame. `delete` events already carry a plain
  # id string, so pass binaries through untouched.
  defp encode_payload(payload) when is_binary(payload), do: payload
  defp encode_payload(payload), do: Jason.encode!(payload)

  defp schedule_heartbeat, do: Process.send_after(self(), :heartbeat, @heartbeat_ms)
end
