# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Outbox.PullConsumer do
  @moduledoc """
  Durable JetStream pull consumer for the OUTBOX stream.

  The OUTBOX stream is configured with `retention=workq` (see
  `infra/nats/bootstrap.sh`), so once we ACK a message it's removed
  from the stream — that's what bounds the stream size.

  Routing + side effects live in `SukhiDelivery.Outbox.Consumer`. This
  module's only job is:

    1. Speak the JetStream pull-consumer protocol.
    2. Map `dispatch/2` return values to `:ack` / `:nack` / `:term`.

  Ack policy:

    * `:ok`, `:no_recipients`, `:ignored`, `:no_handler`,
      `:no_actor`, `:no_followee`, `:missing_account`, `:missing_fields`,
      `:bad_json`  — ACK. Retry can't help.
    * `:translate_failed`  — NACK. Transient (Bun service down, etc).
    * `:crashed`           — NACK. The stack trace was logged in
      `Consumer.handle_event/2`; redelivery may succeed.

  Hard cap on redelivery is enforced by the consumer's
  `:max_deliver` (configured in bootstrap.sh).
  """

  use Gnat.Jetstream.PullConsumer

  require Logger

  alias SukhiDelivery.Outbox.Consumer

  @stream_name "OUTBOX"
  @consumer_name "delivery-outbox"

  def start_link(opts \\ []) do
    Gnat.Jetstream.PullConsumer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    {:ok, nil,
     connection_name: :gnat,
     stream_name: @stream_name,
     consumer_name: @consumer_name}
  end

  @impl true
  def handle_message(%{topic: subject, body: body}, state) do
    case Consumer.handle_event(subject, body) do
      :translate_failed -> {:nack, state}
      :crashed -> {:nack, state}
      _ -> {:ack, state}
    end
  end
end
