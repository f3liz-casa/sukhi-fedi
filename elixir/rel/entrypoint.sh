#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Container entrypoint: run all pending migrations (core + enabled
# addons), then hand off to the release boot script. Watchtower-based
# deployments rely on this — a new image tag lands, the container
# restarts, and migrations flow in automatically.
set -eu

# Mix release reads RELEASE_COOKIE for distributed Erlang. docker-compose
# pre-maps `ERLANG_COOKIE` → `RELEASE_COOKIE`, but Kamal env doesn't
# support variable indirection, so we do the same rename here. Without
# this, gateway and api boot with different build-time default cookies
# and Node.connect/1 silently returns false → /api/v1/* → 503
# plugin_unavailable.
: "${ERLANG_COOKIE:=}"
if [ -n "$ERLANG_COOKIE" ] && [ -z "${RELEASE_COOKIE:-}" ]; then
  export RELEASE_COOKIE="$ERLANG_COOKIE"
fi

/app/bin/sukhi_fedi eval 'SukhiFedi.Release.migrate_all()'
exec /app/bin/sukhi_fedi start
