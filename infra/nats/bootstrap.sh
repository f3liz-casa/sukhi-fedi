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
  --retention=workqueue \
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
