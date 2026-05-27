#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Plugin api node entrypoint. The image's CMD used to be
# `bin/sukhi_api start` directly, but Kamal passes the cluster cookie
# as `ERLANG_COOKIE` while Mix releases read `RELEASE_COOKIE`, so we
# rename it here before handing off. See the matching block in
# elixir/rel/entrypoint.sh for the gateway side.
set -eu

: "${ERLANG_COOKIE:=}"
if [ -n "$ERLANG_COOKIE" ] && [ -z "${RELEASE_COOKIE:-}" ]; then
  export RELEASE_COOKIE="$ERLANG_COOKIE"
fi

# Cluster sanity log (sha256 prefix only). Compare against the
# gateway's `[entrypoint] gateway cookie_fp=` line — they must match
# for Node.connect/1 to succeed.
COOKIE_FP=$(printf '%s' "${RELEASE_COOKIE:-(unset)}" | sha256sum | head -c 16)
echo "[entrypoint] api cookie_fp=$COOKIE_FP"

exec /app/bin/sukhi_api start
