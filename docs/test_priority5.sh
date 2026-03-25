#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Test Priority 5: Moderation & Extended UX

set -e

BASE_URL="${BASE_URL:-http://localhost:4000}"
TOKEN1="${TOKEN1:-test-token-1}"
TOKEN2="${TOKEN2:-test-token-2}"
ADMIN_TOKEN="${ADMIN_TOKEN:-test-admin-token}"

echo "=== Priority 5: Moderation & Extended UX Tests ==="
echo

# Test 1: Mute user
echo "Test 1: Mute user"
curl -s -X POST "$BASE_URL/api/mute" \
  -H "Authorization: Bearer $TOKEN1" \
  -H "Content-Type: application/json" \
  -d '{"target_id": 2}' | jq .
echo

# Test 2: Block user
echo "Test 2: Block user"
curl -s -X POST "$BASE_URL/api/block" \
  -H "Authorization: Bearer $TOKEN1" \
  -H "Content-Type: application/json" \
  -d '{"target_id": 3}' | jq .
echo

# Test 3: Create report
echo "Test 3: Create abuse report"
curl -s -X POST "$BASE_URL/api/reports" \
  -H "Authorization: Bearer $TOKEN1" \
  -H "Content-Type: application/json" \
  -d '{"target_id": 2, "comment": "Test report"}' | jq .
echo

# Test 4: Bookmark note
echo "Test 4: Bookmark note"
curl -s -X POST "$BASE_URL/api/bookmarks" \
  -H "Authorization: Bearer $TOKEN1" \
  -H "Content-Type: application/json" \
  -d '{"note_id": 1}' | jq .
echo

# Test 5: List bookmarks
echo "Test 5: List bookmarks"
curl -s -X GET "$BASE_URL/api/bookmarks?limit=10" \
  -H "Authorization: Bearer $TOKEN1" | jq .
echo

# Test 6: Create article
echo "Test 6: Create article"
curl -s -X POST "$BASE_URL/api/articles" \
  -H "Authorization: Bearer $TOKEN1" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Article",
    "content": "This is a long-form article with multiple paragraphs...",
    "summary": "A test article"
  }' | jq .
echo

# Test 7: List articles
echo "Test 7: List articles"
curl -s -X GET "$BASE_URL/api/articles?limit=10" | jq .
echo

# Admin tests (require admin token)
echo "=== Admin Tests ==="
echo

# Test 8: List reports (admin)
echo "Test 8: List reports (admin)"
curl -s -X GET "$BASE_URL/api/admin/reports?status=open" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq .
echo

# Test 9: Block instance (admin)
echo "Test 9: Block instance (admin)"
curl -s -X POST "$BASE_URL/api/admin/instance-blocks" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "spam.example.com",
    "severity": "suspend",
    "reason": "Spam source"
  }' | jq .
echo

# Test 10: List instance blocks (admin)
echo "Test 10: List instance blocks (admin)"
curl -s -X GET "$BASE_URL/api/admin/instance-blocks" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq .
echo

# Test 11: Unmute user
echo "Test 11: Unmute user"
curl -s -X DELETE "$BASE_URL/api/mute" \
  -H "Authorization: Bearer $TOKEN1" \
  -H "Content-Type: application/json" \
  -d '{"target_id": 2}' | jq .
echo

# Test 12: Unblock user
echo "Test 12: Unblock user"
curl -s -X DELETE "$BASE_URL/api/block" \
  -H "Authorization: Bearer $TOKEN1" \
  -H "Content-Type: application/json" \
  -d '{"target_id": 3}' | jq .
echo

# Test 13: Delete bookmark
echo "Test 13: Delete bookmark"
curl -s -X DELETE "$BASE_URL/api/bookmarks" \
  -H "Authorization: Bearer $TOKEN1" \
  -H "Content-Type: application/json" \
  -d '{"note_id": 1}' | jq .
echo

echo "=== All Priority 5 tests complete ==="
