# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Addons.Streaming do
  @moduledoc """
  Streaming addon — WebSocket/SSE pub-sub for home/local/public feeds.

  Subscribes to the `stream.new_post` NATS subject and fans out events
  to connected clients through `SukhiFedi.Addons.Streaming.Registry`.
  """

  use SukhiFedi.Addon, id: :streaming

  alias SukhiFedi.Addons.Streaming

  @impl true
  def supervision_children do
    [Streaming.Registry, Streaming.NatsListener]
  end
end
