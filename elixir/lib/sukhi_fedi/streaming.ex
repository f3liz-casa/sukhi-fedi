# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Streaming do
  @moduledoc """
  Gateway entry point for pushing events to connected streaming clients.

  The streaming sockets and their broadcaster Registry live on the
  gateway (see `SukhiFedi.Addons.Streaming`), but Mastodon entities are
  rendered on the api plugin node (it owns the views). So the api renders
  a payload and calls in here via `GatewayRpc` — rendering stays on the
  api, fan-out stays where the sockets are.

  Best-effort by design: streaming is an optional addon, so when its
  Registry isn't running these calls are a no-op rather than an error. A
  dropped stream frame must never fail the write that produced it.
  """

  alias SukhiFedi.Addons.Streaming.Registry

  @doc """
  Push a freshly-created DM to each local participant's `direct` stream.
  `targets` is `[%{account_id, conversation}]` where `conversation` is an
  already-rendered Mastodon Conversation map (viewer-relative).
  """
  @spec publish_direct([%{account_id: integer(), conversation: map()}]) :: :ok
  def publish_direct(targets) when is_list(targets) do
    if registry_running?() do
      Enum.each(targets, fn %{account_id: account_id, conversation: conversation} ->
        Registry.broadcast(:direct, %{event: "conversation", payload: conversation}, account_id)
      end)
    end

    :ok
  end

  defp registry_running?, do: is_pid(Process.whereis(Registry))
end
