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

exec /app/bin/sukhi_api start
