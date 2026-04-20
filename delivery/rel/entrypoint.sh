#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Delivery container entrypoint. Schema is owned by the gateway release,
# so we don't run migrations here — the gateway container ran them first
# (docker-compose `depends_on: gateway`). If the delivery app later grows
# its own tables, wire them into `SukhiDelivery.Release.migrate_all/0`
# and add a call here.
set -eu

exec /app/bin/sukhi_delivery start
