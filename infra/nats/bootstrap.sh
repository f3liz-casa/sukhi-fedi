#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Bootstrap NATS JetStream streams for sukhi-fedi.
#
# Usage:
#   NATS_URL=nats://nats:4222 ./infra/nats/bootstrap.sh
#
# Requires the `nats` CLI (bundled in the natsio/nats-box image,
# or install from https://github.com/nats-io/natscli/releases).
#
# Idempotent: streams that already exist are left untouched.
# If you need to change stream config, use `nats stream edit` manually.
set -eu

NATS_URL="${NATS_URL:-nats://localhost:4222}"

echo "[bootstrap] NATS_URL=$NATS_URL"

nats_cli() {
  nats --server "$NATS_URL" "$@"
}

ensure_stream() {
  name="$1"
  shift
  if nats_cli stream info "$name" >/dev/null 2>&1; then
    echo "[bootstrap] stream '$name' already exists, skipping"
    return 0
  fi
  echo "[bootstrap] creating stream '$name'"
  nats_cli stream add "$name" "$@"
}

# OUTBOX: Transactional Outbox relay.
# WorkQueue retention = each message consumed exactly once across subjects.
# Durable consumers (Elixir ap-deliverer, timeline-updater) will pull from here.
# dupe-window 2m handles Elixir Outbox.Relay retries with Nats-Msg-Id.
ensure_stream OUTBOX \
  --subjects="sns.outbox.>" \
  --storage=file \
  --retention=workq \
  --replicas=1 \
  --discard=old \
  --dupe-window=2m \
  --max-msgs=-1 \
  --max-bytes=-1 \
  --max-age=0s \
  --max-msgs-per-subject=-1 \
  --max-msg-size=-1 \
  --no-allow-rollup \
  --no-deny-delete \
  --no-deny-purge

ensure_consumer() {
  stream="$1"
  consumer="$2"
  shift 2
  if nats_cli consumer info "$stream" "$consumer" >/dev/null 2>&1; then
    echo "[bootstrap] consumer '$stream/$consumer' already exists, skipping"
    return 0
  fi
  echo "[bootstrap] creating consumer '$stream/$consumer'"
  nats_cli consumer add "$stream" "$consumer" "$@"
}

# Durable pull consumer for SukhiDelivery.Outbox.PullConsumer.
# WorkQueue stream + explicit ACK = each event handled exactly once,
# then removed from OUTBOX. Redelivery on NACK / ack timeout.
#
# --max-deliver is the *backstop*. The consumer itself governs retries
# (PullConsumer @max_attempts = 12, exponential backoff) and dead-letters
# to OUTBOX_DLQ before this cap is hit. Keep it strictly greater than
# @max_attempts, or JetStream stops redelivering before the app can
# capture the message. (Was 5 — too low: with Bun gone the gateway is the
# only translator, and its restart could burn the budget in under a
# second and silently drop the activity.)
#
# Existing deploys: ensure_consumer is a no-op once the consumer exists,
# so bump a live one in place:
#   nats consumer edit OUTBOX delivery-outbox --max-deliver=16
ensure_consumer OUTBOX delivery-outbox \
  --defaults \
  --pull \
  --deliver=all \
  --filter="sns.outbox.>" \
  --ack=explicit \
  --wait=30s \
  --max-deliver=16 \
  --replay=instant

# OUTBOX_DLQ: dead-letter for outbound activities that exhausted the
# delivery consumer's retry budget (translator down too long). Limits
# retention with a 30-day TTL so a failed activity can be inspected and
# replayed (republish sns.outbox_dlq.X → sns.outbox.X) rather than lost.
ensure_stream OUTBOX_DLQ \
  --subjects="sns.outbox_dlq.>" \
  --storage=file \
  --retention=limits \
  --replicas=1 \
  --discard=old \
  --dupe-window=2m \
  --max-msgs=-1 \
  --max-bytes=-1 \
  --max-age=720h \
  --max-msgs-per-subject=-1 \
  --max-msg-size=-1 \
  --no-allow-rollup \
  --no-deny-delete \
  --no-deny-purge

# DOMAIN_EVENTS: broadcast events (WebSocket streaming, notifications).
# Limits retention with 7-day TTL so consumers can replay after reconnect.
ensure_stream DOMAIN_EVENTS \
  --subjects="sns.events.>" \
  --storage=file \
  --retention=limits \
  --replicas=1 \
  --discard=old \
  --dupe-window=2m \
  --max-msgs=-1 \
  --max-bytes=-1 \
  --max-age=168h \
  --max-msgs-per-subject=-1 \
  --max-msg-size=-1 \
  --no-allow-rollup \
  --no-deny-delete \
  --no-deny-purge

echo "[bootstrap] done. current streams:"
nats_cli stream ls
