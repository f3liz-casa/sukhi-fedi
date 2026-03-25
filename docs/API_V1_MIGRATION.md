# API v1 Migration Summary

## Overview

The API has been refactored to follow a consistent v1 structure with:
- Unified endpoint paths under `/api/v1/`
- Consistent error response format
- RESTful resource-based routing
- URN-based feed/streaming endpoints

## Key Changes

### Authentication
- **Old:** Multiple endpoints (`/api/auth/webauthn/*`)
- **New:** Single unified endpoint `POST /api/v1/auth/session`
  - Supports both passkey and password authentication via `type` field
  - Returns `{token, account_id}` on success

### Identity & Profiles
- **New:** `GET /api/v1/me` - Get authenticated user
- **Updated:** `GET /api/v1/users/:username` - Get user profile
- **New:** `PATCH /api/v1/relationships/:id` - Unified follow/mute/block management

### Content Management
- **Updated:** `POST /api/v1/notes` - Supports `type` field for Note/Boost/Article
- **New:** `GET /api/v1/notes/:id` - Get specific note
- **New:** `DELETE /api/v1/notes/:id` - Delete note

### Reactions
- **Old:** `POST /api/reactions` with `note_id` in body
- **New:** `PUT /api/v1/notes/:id/reactions` - Add reaction to note
- **New:** `DELETE /api/v1/notes/:id/reactions/:emoji` - Remove reaction (URL-encoded emoji)

### Polls
- **Old:** `POST /api/polls/vote` with `poll_id`
- **New:** `POST /api/v1/notes/:id/vote` - Vote on poll attached to note
- Supports multiple choices via `choices` array

### Feeds & Streaming
- **Old:** Separate endpoints (`/api/feeds/home`, `/api/feeds/local`)
- **New:** URN-based routing
  - `GET /api/v1/feeds/:urn` where urn = `home|local|public`
  - `GET /api/v1/streaming/:urn` where urn = `home|local|public`
- Pagination uses `cursor` instead of `max_id`

### Media
- **Old:** `POST /api/media/upload-url`
- **New:** `POST /api/v1/media/presigned` - Request upload URL
- **New:** `POST /api/v1/media` - Register uploaded media

### Bookmarks
- **Old:** `DELETE /api/bookmarks` with `note_id` in body
- **New:** `DELETE /api/v1/bookmarks/:note_id` - RESTful deletion
- Pagination uses cursor-based approach

### Emojis
- **Updated:** `GET /api/v1/emojis` - List emojis (public)
- **New:** Admin-only endpoints moved to `/api/admin/emojis`

## Error Response Format

All errors now follow consistent structure:

```json
{
  "error": "error_code",
  "message": "Human-readable message"
}
```

Common error codes:
- `invalid_token` - Authentication failed
- `invalid_request` - Bad request payload
- `validation_error` - Validation failed
- `not_found` - Resource not found
- `forbidden` - Insufficient permissions

## HTTP Status Codes

- `200` - Success
- `201` - Created
- `204` - No Content (successful deletion)
- `400` - Bad Request
- `401` - Unauthorized
- `403` - Forbidden
- `404` - Not Found
- `422` - Unprocessable Entity

## Migration Guide

### For Clients

1. **Update base path:** All API calls should use `/api/v1/` prefix
2. **Authentication:** Use `POST /api/v1/auth/session` with type field
3. **Reactions:** Use note ID in URL path, not body
4. **Feeds:** Use URN parameter instead of separate endpoints
5. **Pagination:** Use `cursor` parameter instead of `max_id`
6. **Error handling:** Parse `error` and `message` fields

### Example Migrations

**Old:**
```bash
POST /api/reactions
{"note_id": "123", "emoji": "👍"}
```

**New:**
```bash
PUT /api/v1/notes/123/reactions
{"emoji": "👍"}
```

---

**Old:**
```bash
GET /api/feeds/home?max_id=100&limit=20
```

**New:**
```bash
GET /api/v1/feeds/home?cursor=100&limit=20
```

---

**Old:**
```bash
POST /api/follow
{"username": "alice"}
```

**New:**
```bash
PATCH /api/v1/relationships/alice_id
{"follow": true}
```

## Backward Compatibility

Legacy endpoints have been removed. Clients must migrate to v1 API.

## Testing

Update test scripts to use new endpoints:
```bash
# Test authentication
curl -X POST http://localhost:4000/api/v1/auth/session \
  -H "Content-Type: application/json" \
  -d '{"type": "password", "username": "alice", "password": "secret"}'

# Test feeds
curl http://localhost:4000/api/v1/feeds/local?limit=10

# Test streaming
curl http://localhost:4000/api/v1/streaming/local
```
