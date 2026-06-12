#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Combined (gateway + delivery in one BEAM) container entrypoint.
# Same contract as the gateway's: run all pending migrations, then
# hand off to the release boot script. Delivery never migrates —
# schema stays gateway-owned even when the apps share a VM.
set -eu

# ERLANG_COOKIE → RELEASE_COOKIE rename, same as the gateway entrypoint
# (Kamal env can't do variable indirection).
: "${ERLANG_COOKIE:=}"
if [ -n "$ERLANG_COOKIE" ] && [ -z "${RELEASE_COOKIE:-}" ]; then
  export RELEASE_COOKIE="$ERLANG_COOKIE"
fi

# Fail closed: the distribution cookie is the only auth for Erlang
# distribution. Refuse to boot with no cookie or the published dev
# default.
if [ -z "${RELEASE_COOKIE:-}" ] || [ "${RELEASE_COOKIE:-}" = "sukhi_fedi_dev_cookie" ]; then
  echo "[entrypoint] refusing to boot: set ERLANG_COOKIE to a random secret (openssl rand -hex 32)" >&2
  exit 1
fi

COOKIE_FP=$(printf '%s' "${RELEASE_COOKIE:-(unset)}" | sha256sum | head -c 16)
echo "[entrypoint] combined cookie_fp=$COOKIE_FP"

/app/bin/combined eval 'SukhiFedi.Release.migrate_all()'
exec /app/bin/combined start
