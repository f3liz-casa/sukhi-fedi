#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Mastodon-flavoured curl walkthrough against a running sukhi-fedi
# instance. Exercises the OAuth dance, posting a status, and a media
# upload — i.e. the smallest path that proves the REST surface is
# wired to the gateway.
#
# Usage:
#   BASE_URL=http://localhost:4000 ./scripts/smoke.sh <username> <password>
#
# Defaults:
#   BASE_URL=http://localhost:4000
#   APP_NAME=smoke
#
# The script is intentionally chatty so a regression in any step is
# obvious from the failing curl output rather than a downstream NPE.

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
APP_NAME="${APP_NAME:-smoke}"
USERNAME="${1:-}"
PASSWORD="${2:-}"

if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
  echo "usage: $0 <username> <password>"
  exit 2
fi

echo "[1/6] Registering OAuth app '$APP_NAME' on $BASE_URL …"
app=$(curl -fsS -X POST "$BASE_URL/api/v1/apps" \
  -H "content-type: application/json" \
  -d "{\"client_name\":\"$APP_NAME\",\"redirect_uris\":\"urn:ietf:wg:oauth:2.0:oob\",\"scopes\":\"read write follow\"}")
echo "  → $app"

client_id=$(echo "$app" | jq -r .client_id)
client_secret=$(echo "$app" | jq -r .client_secret)

echo "[2/6] Password grant for '$USERNAME' …"
tok=$(curl -fsS -X POST "$BASE_URL/oauth/token" \
  -H "content-type: application/json" \
  -d "{\"grant_type\":\"password\",\"client_id\":\"$client_id\",\"client_secret\":\"$client_secret\",\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"scope\":\"read write follow\"}")
echo "  → $tok"

access_token=$(echo "$tok" | jq -r .access_token)
auth=("-H" "authorization: Bearer $access_token")

echo "[3/6] verify_credentials …"
me=$(curl -fsS "$BASE_URL/api/v1/accounts/verify_credentials" "${auth[@]}")
echo "  → $(echo "$me" | jq -c '{id,username,display_name,statuses_count}')"

echo "[4/6] Post a status …"
ts=$(date -u +%FT%TZ)
post=$(curl -fsS -X POST "$BASE_URL/api/v1/statuses" "${auth[@]}" \
  -H "content-type: application/json" \
  -d "{\"status\":\"smoke test #ping at $ts\",\"visibility\":\"public\"}")
echo "  → $(echo "$post" | jq -c '{id,visibility,uri}')"

status_id=$(echo "$post" | jq -r .id)

echo "[5/6] Read it back from the home timeline …"
home=$(curl -fsS "$BASE_URL/api/v1/timelines/home?limit=5" "${auth[@]}")
echo "  → home has $(echo "$home" | jq 'length') statuses"

echo "[6/6] Upload a 1-px PNG to media …"
png=$(mktemp -t smoke.XXXX.png)
# 1×1 transparent PNG
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82' > "$png"

media=$(curl -fsS -X POST "$BASE_URL/api/v2/media" "${auth[@]}" \
  -F "file=@$png;type=image/png" \
  -F "description=smoke 1x1")
echo "  → $(echo "$media" | jq -c '{id,type,url}')"

media_id=$(echo "$media" | jq -r .id)

echo "[6.b] Post a status with that media …"
post_media=$(curl -fsS -X POST "$BASE_URL/api/v1/statuses" "${auth[@]}" \
  -H "content-type: application/json" \
  -d "{\"status\":\"with attachment\",\"visibility\":\"unlisted\",\"media_ids\":[\"$media_id\"]}")
echo "  → $(echo "$post_media" | jq -c '{id,visibility,media_attachments:.media_attachments|length}')"

rm -f "$png"

echo
echo "smoke OK — created statuses: $status_id, $(echo "$post_media" | jq -r .id)"
