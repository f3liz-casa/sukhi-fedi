# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Outbox.PullConsumer do
  @moduledoc """
  Durable JetStream pull consumer for the OUTBOX stream.

  The OUTBOX stream is `retention=workq` (see `infra/nats/bootstrap.sh`),
  so once we ACK a message it's removed — that's what bounds the stream.

  Routing + side effects live in `SukhiDelivery.Outbox.Consumer`. This
  module owns the ack policy:

    * structural results (`:ok`, `:no_recipients`, `:ignored`,
      `:no_handler`, `:no_actor`, `:no_followee`, `:missing_account`,
      `:missing_fields`, `:bad_json`) — ACK. Retry can't help.
    * transient results (`:translate_failed`, `:crashed`) — the translator
      (the gateway's native `fedify.*` service) is the only signer now that
      the Bun sidecar is gone, so a gateway restart / OOM makes *every*
      outbound activity fail to translate for a few seconds. We must not
      lose those.

  So a transient failure is **not** a plain NACK (which JetStream would
  redeliver instantly, burning the whole `max_deliver` budget in well under
  a second and silently dropping the message). Instead:

    1. Redeliver with an **exponential backoff** (`@backoff_s`) — a delayed
       `-NAK`, so a brief translator outage is simply waited out.
    2. On the final attempt (`@max_attempts`), republish the message to the
       **`OUTBOX_DLQ` stream** and ACK, so it's captured for inspection /
       replay rather than vanishing.

  `@max_attempts` must stay `<=` the JetStream consumer's `max_deliver`
  (bootstrap.sh sets 16) — otherwise JetStream stops redelivering before we
  reach the dead-letter step.
  """

  use Gnat.Jetstream.PullConsumer

  require Logger

  alias SukhiDelivery.Outbox.Consumer

  @stream_name "OUTBOX"
  @consumer_name "delivery-outbox"

  @transient [:translate_failed, :crashed]

  # Retry budget for transient failures. Delay (seconds) before the n-th
  # redelivery; the last value repeats. 11 spaced retries (~27 min total)
  # then dead-letter on the 12th delivery.
  @backoff_s [5, 10, 20, 40, 60, 120, 180, 300, 300, 300, 300]
  @max_attempts 12

  @outbox_prefix "sns.outbox."
  @dlq_prefix "sns.outbox_dlq."

  def start_link(opts \\ []) do
    Gnat.Jetstream.PullConsumer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    {:ok, nil,
     connection_name: :gnat_delivery,
     stream_name: @stream_name,
     consumer_name: @consumer_name}
  end

  @impl true
  def handle_message(%{topic: subject, body: body} = message, state) do
    case Consumer.handle_event(subject, body) do
      result when result in @transient ->
        retry_or_dead_letter(message, subject, body, state)

      _ ->
        {:ack, state}
    end
  end

  defp retry_or_dead_letter(message, subject, body, state) do
    if delivered_count(message.reply_to) >= @max_attempts do
      dead_letter(message, subject, body, state)
    else
      nack_after(message, backoff_ms(delivered_count(message.reply_to)))
      {:noreply, state}
    end
  end

  defp dead_letter(message, subject, body, state) do
    case Gnat.pub(message.gnat, dlq_subject(subject), body) do
      :ok ->
        Logger.error(
          "outbox dead-letter after #{@max_attempts} attempts: #{subject} → #{dlq_subject(subject)}"
        )

        :telemetry.execute([:sukhi_delivery, :outbox, :dead_letter], %{count: 1}, %{
          subject: subject
        })

        {:ack, state}

      other ->
        # Couldn't capture it — keep it in the workqueue rather than lose it.
        Logger.warning("outbox DLQ publish failed (#{inspect(other)}); retrying: #{subject}")
        {:nack, state}
    end
  end

  # A delayed negative-ack: tell JetStream to redeliver after `delay_ms`,
  # so a transient translator outage is waited out instead of burned
  # through. (`Gnat.Jetstream.nack/1` has no delay; we speak the ack
  # protocol directly.)
  defp nack_after(%{gnat: gnat, reply_to: reply_to}, delay_ms) when is_binary(reply_to) do
    Gnat.pub(gnat, reply_to, "-NAK " <> JSON.encode!(%{delay: delay_ms * 1_000_000}))
  end

  # ── pure helpers (unit-tested) ─────────────────────────────────────────────

  @doc """
  The JetStream delivery count from a message's ack `reply_to` subject
  (`$JS.ACK.<…>.<delivered>.<stream_seq>.<consumer_seq>.<ts>.<pending>[.token]`).
  The token layout differs by server version (with/without a JetStream
  domain, with/without a trailing random token), so we locate `delivered`
  robustly. Unknown shape → `1` (retry; JetStream's max_deliver is the
  backstop) rather than forcing a premature dead-letter.
  """
  @spec delivered_count(binary() | nil) :: pos_integer()
  def delivered_count(reply_to) when is_binary(reply_to) do
    parts = String.split(reply_to, ".")
    n = length(parts)
    idx = if n >= 12, do: 6, else: n - 5

    with true <- idx >= 0,
         token when is_binary(token) <- Enum.at(parts, idx),
         {count, ""} <- Integer.parse(token) do
      count
    else
      _ -> 1
    end
  end

  def delivered_count(_), do: 1

  @doc "Backoff in ms before the redelivery following `attempt` (1-based)."
  @spec backoff_ms(pos_integer()) :: pos_integer()
  def backoff_ms(attempt) when attempt >= 1 do
    idx = min(attempt, length(@backoff_s)) - 1
    Enum.at(@backoff_s, idx) * 1000
  end

  @doc "Map an OUTBOX subject to its dead-letter counterpart."
  @spec dlq_subject(binary()) :: binary()
  def dlq_subject(@outbox_prefix <> rest), do: @dlq_prefix <> rest
  def dlq_subject(subject), do: @dlq_prefix <> subject

  @doc false
  def max_attempts, do: @max_attempts
end
