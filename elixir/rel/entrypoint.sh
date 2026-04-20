#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Container entrypoint: run all pending migrations (core + enabled
# addons), then hand off to the release boot script. Watchtower-based
# deployments rely on this — a new image tag lands, the container
# restarts, and migrations flow in automatically.
set -eu

/app/bin/sukhi_fedi eval 'SukhiFedi.Release.migrate_all()'
exec /app/bin/sukhi_fedi start
