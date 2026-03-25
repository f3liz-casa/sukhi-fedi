#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Test script for real-time streaming

set -e

BASE_URL="http://localhost:4000"

echo "=== Real-Time Streaming Test ==="
echo

# 1. Register account
echo "1. Creating test account..."
REGISTER_RESP=$(curl -s -X POST "$BASE_URL/api/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"username":"streamer","password":"test123"}')
echo "Response: $REGISTER_RESP"
echo

# 2. Login to get token
echo "2. Logging in..."
# Note: This assumes you have a login endpoint that returns a token
# Adjust based on your actual auth flow
echo

# 3. Test local feed (HTTP)
echo "3. Fetching local feed (HTTP)..."
curl -s "$BASE_URL/api/feeds/local" | jq '.'
echo

# 4. Test home feed (HTTP) - requires auth
echo "4. Fetching home feed (HTTP) - requires Bearer token..."
echo "   curl -H 'Authorization: Bearer YOUR_TOKEN' $BASE_URL/api/feeds/home"
echo

# 5. Test SSE streaming
echo "5. Testing SSE streaming (local feed)..."
echo "   Open in browser or use:"
echo "   curl -N $BASE_URL/api/streaming/local"
echo

echo "6. Testing SSE streaming (home feed) - requires auth..."
echo "   curl -N -H 'Authorization: Bearer YOUR_TOKEN' $BASE_URL/api/streaming/home"
echo

echo "=== Test Complete ==="
echo
echo "To test real-time updates:"
echo "1. Open SSE stream: curl -N $BASE_URL/api/streaming/local"
echo "2. In another terminal, create a post:"
echo "   curl -X POST $BASE_URL/api/notes \\"
echo "     -H 'Authorization: Bearer YOUR_TOKEN' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"content\":\"Hello real-time!\"}'"
echo
echo "You should see the post appear in the SSE stream immediately!"
