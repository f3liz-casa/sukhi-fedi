#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Nightly off-host backup for sukhi-fedi: a logical Postgres dump + the rustfs
# object store (media + inbound/outbound archives) + rotated container logs,
# all into one encrypted, deduplicated restic snapshot on Backblaze B2.
#
# DORMANT until installed — see infra/backup/README.md. Secrets come from
# /etc/sukhi-fedi/backup.env via the systemd unit.
set -euo pipefail

: "${RESTIC_REPOSITORY:?set in backup.env}"
: "${RESTIC_PASSWORD:?set in backup.env}"
: "${PGPASSWORD:?set in backup.env}"
PG_CONTAINER="${PG_CONTAINER:-sukhi-fedi-postgres}"
PG_USER="${PG_USER:-sukhi}"
PG_DB="${PG_DB:-sukhi_fedi}"
RUSTFS_DATA_DIR="${RUSTFS_DATA_DIR:-/home/rocky/sukhi-fedi-rustfs/data}"
DOCKER_CONTAINERS_DIR="${DOCKER_CONTAINERS_DIR:-}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"

log() { echo "[sukhi-backup] $*"; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

ts="$(date -u +%Y%m%dT%H%M%SZ)"
dump="$stage/${PG_DB}-${ts}.dump"

# Logical dump via the running postgres container — pg_dump version always
# matches the server, and -Fc keeps selective single-table pg_restore. restic
# does the compression (--compression max), so no -Z / external zstd here.
log "pg_dump ${PG_DB} from ${PG_CONTAINER}"
docker exec -e PGPASSWORD="$PGPASSWORD" "$PG_CONTAINER" \
  pg_dump -Fc -U "$PG_USER" "$PG_DB" >"$dump"
log "dump size: $(du -h "$dump" | cut -f1)"

# First run on a fresh repo: init. No-op once it exists.
restic snapshots >/dev/null 2>&1 || { log "initializing restic repo"; restic init; }

paths=("$dump" "$RUSTFS_DATA_DIR")
if [ -n "$DOCKER_CONTAINERS_DIR" ] && [ -d "$DOCKER_CONTAINERS_DIR" ]; then
  paths+=("$DOCKER_CONTAINERS_DIR")
fi

log "restic backup: ${paths[*]}"
restic backup --tag sukhi-fedi --host sukhi-fedi --compression max "${paths[@]}"

log "restic forget (retention)"
restic forget --tag sukhi-fedi \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

log "done"

# Dead-man ping — only reached on full success (set -e bails earlier on error).
if [ -n "$HEALTHCHECK_URL" ]; then
  curl -fsS -m 10 "$HEALTHCHECK_URL" >/dev/null && log "pinged healthcheck" || true
fi
