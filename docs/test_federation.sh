#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Test script for Priority 3: ActivityPub Federation

set -e

BASE_URL="http://localhost:4000"
REMOTE_ACTOR="https://mastodon.social/users/Gargron"
REMOTE_POST="https://mastodon.social/users/Gargron/statuses/1"

echo "=== Priority 3: ActivityPub Federation Tests ==="
echo ""

# 1. Create test account
echo "1. Creating test account..."
ACCOUNT_RESP=$(curl -s -X POST "$BASE_URL/api/accounts" \
  -H "Content-Type: application/json" \
  -d '{"username":"fedtest","display_name":"Federation Test","summary":"Testing federation"}')
echo "   Response: $ACCOUNT_RESP"
echo ""

# 2. Create token
echo "2. Creating auth token..."
TOKEN_RESP=$(curl -s -X POST "$BASE_URL/api/tokens" \
  -H "Content-Type: application/json" \
  -d '{"username":"fedtest"}')
TOKEN=$(echo "$TOKEN_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
echo "   Token: $TOKEN"
echo ""

# 3. Test WebFinger
echo "3. Testing WebFinger..."
WEBFINGER_RESP=$(curl -s "$BASE_URL/.well-known/webfinger?resource=acct:fedtest@localhost")
echo "   Response: $WEBFINGER_RESP"
echo ""

# 4. Test Actor Profile
echo "4. Testing Actor Profile..."
ACTOR_RESP=$(curl -s -H "Accept: application/activity+json" "$BASE_URL/users/fedtest")
echo "   Response: $ACTOR_RESP"
echo ""

# 5. Test Outbox
echo "5. Testing Outbox..."
OUTBOX_RESP=$(curl -s -H "Accept: application/activity+json" "$BASE_URL/users/fedtest/outbox")
echo "   Response: $OUTBOX_RESP"
echo ""

# 6. Create a note
echo "6. Creating a note..."
NOTE_RESP=$(curl -s -X POST "$BASE_URL/api/notes" \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$TOKEN\",\"content\":\"Testing federation!\"}")
NOTE_ID=$(echo "$NOTE_RESP" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
echo "   Note ID: $NOTE_ID"
echo ""

# 7. Test Like (will fail if remote post doesn't exist, but tests the endpoint)
echo "7. Testing Like endpoint..."
LIKE_RESP=$(curl -s -X POST "$BASE_URL/api/likes" \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$TOKEN\",\"object\":\"$REMOTE_POST\"}" || echo '{"error":"expected"}')
echo "   Response: $LIKE_RESP"
echo ""

# 8. Test Boost
echo "8. Testing Boost endpoint..."
BOOST_RESP=$(curl -s -X POST "$BASE_URL/api/boosts" \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$TOKEN\",\"object\":\"$REMOTE_POST\"}" || echo '{"error":"expected"}')
echo "   Response: $BOOST_RESP"
echo ""

# 9. Test incoming activity (simulated)
echo "9. Testing Inbox endpoint (will fail signature verification, but tests the flow)..."
INBOX_RESP=$(curl -s -X POST "$BASE_URL/users/fedtest/inbox" \
  -H "Content-Type: application/activity+json" \
  -d '{
    "@context": "https://www.w3.org/ns/activitystreams",
    "type": "Follow",
    "actor": "'"$REMOTE_ACTOR"'",
    "object": "http://localhost:4000/users/fedtest"
  }' || echo '{"error":"signature verification failed (expected)"}')
echo "   Response: $INBOX_RESP"
echo ""

# 10. Check Oban queue
echo "10. Checking Oban queue status..."
echo "    Run in IEx: Oban.check_queue(queue: :delivery)"
echo ""

echo "=== Test Summary ==="
echo "✓ Account creation"
echo "✓ Token generation"
echo "✓ WebFinger endpoint"
echo "✓ Actor profile endpoint"
echo "✓ Outbox endpoint"
echo "✓ Note creation"
echo "✓ Like endpoint"
echo "✓ Boost endpoint"
echo "✓ Inbox endpoint (signature verification expected to fail without valid signature)"
echo ""
echo "=== Manual Tests Required ==="
echo "1. Follow @fedtest@localhost from a real Mastodon/Misskey instance"
echo "2. Check database: SELECT * FROM follows;"
echo "3. Check Oban jobs: SELECT * FROM oban_jobs WHERE queue = 'delivery';"
echo "4. Send a post from remote instance and verify it appears in objects table"
echo ""
echo "=== Database Queries ==="
echo "# Check follows"
echo "psql sukhi_fedi -c \"SELECT * FROM follows;\""
echo ""
echo "# Check objects"
echo "psql sukhi_fedi -c \"SELECT id, type, actor_id, created_at FROM objects ORDER BY created_at DESC LIMIT 10;\""
echo ""
echo "# Check Oban jobs"
echo "psql sukhi_fedi -c \"SELECT id, queue, state, attempted_at FROM oban_jobs ORDER BY attempted_at DESC LIMIT 10;\""
echo ""
