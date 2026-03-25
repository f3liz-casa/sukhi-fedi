# API Reference

## Federation (Server-to-Server)

### WebFinger Discovery
**Endpoint:** `GET /.well-known/webfinger`  
**Description:** Discover actor information by account identifier  
**Query Parameters:**
```
resource=acct:username@domain.com
```
**Response:** JSON Resource Descriptor (JRD)

### ActivityPub Actor
**Endpoint:** `GET /users/:name`  
**Description:** Get an actor's profile in ActivityStreams format  
**Accept:** `application/activity+json`  
**Response:**
```json
{
  "@context": [
    "https://www.w3.org/ns/activitystreams",
    "https://w3id.org/security/v1"
  ],
  "id": "https://your.domain/users/alice",
  "type": "Person",
  "preferredUsername": "alice",
  "name": "Alice",
  "inbox": "https://your.domain/users/alice/inbox",
  "outbox": "https://your.domain/users/alice/outbox",
  "publicKey": { ... }
}
```

### ActivityPub Outbox
**Endpoint:** `GET /users/:name/outbox`  
**Description:** Get an actor's recently published activities  
**Accept:** `application/activity+json`  
**Response:**
```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "id": "https://your.domain/users/alice/outbox",
  "type": "OrderedCollection",
  "totalItems": 10,
  "orderedItems": [ /* array of activities */ ]
}
```

### User Inbox
**Endpoint:** `POST /users/:name/inbox`  
**Description:** Receive ActivityPub activities for specific user  
**Content-Type:** `application/activity+json`  
**Payload:** ActivityStreams 2.0 JSON-LD object
```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Follow",
  "actor": "https://remote.example/users/alice",
  "object": "https://your.domain/users/bob"
}
```

### Shared Inbox
**Endpoint:** `POST /inbox`  
**Description:** Global inbox for all users (optimized delivery)  
**Content-Type:** `application/activity+json`  
**Payload:** ActivityStreams 2.0 JSON-LD object

---

## Identity & Graph

### Register Account
**Endpoint:** `POST /api/v1/accounts`  
**Description:** Create new user account  
**Payload:**
```json
{
  "username": "alice",
  "password": "secure_password",
  "email": "alice@example.com"
}
```
**Response:**
```json
{
  "token": "eyJ...",
  "account_id": "123"
}
```

### Authentication
**Endpoint:** `POST /api/v1/auth/session`  
**Description:** Authenticate user via passkey or password  
**Payload:**
```json
{
  "type": "passkey",
  "credential": {
    "id": "...",
    "rawId": "...",
    "response": { ... }
  }
}
```
**Response:** Bearer token

### Current User
**Endpoint:** `GET /api/v1/me`  
**Description:** Get authenticated user profile  
**Headers:** `Authorization: Bearer <token>`  
**Response:**
```json
{
  "id": "123",
  "username": "alice",
  "display_name": "Alice",
  "avatar_url": "https://...",
  "created_at": "2026-01-01T00:00:00Z"
}
```

### Update Profile
**Endpoint:** `PATCH /api/v1/me`  
**Description:** Update own profile  
**Headers:** `Authorization: Bearer <token>`  
**Payload:**
```json
{
  "display_name": "Alice Smith",
  "bio": "Software developer",
  "avatar_url": "https://..."
}
```

### User Profile
**Endpoint:** `GET /api/v1/users/:username`  
**Description:** Get public user profile  
**Response:** User object (same as `/me`)

### User Timeline
**Endpoint:** `GET /api/v1/users/:username/notes`  
**Description:** Get user's public notes  
**Query Parameters:**
```
cursor=123    # Pagination cursor
limit=20      # Results per page
```

### Followers List
**Endpoint:** `GET /api/v1/users/:username/followers`  
**Description:** Get user's followers  
**Query Parameters:**
```
cursor=123    # Pagination cursor
limit=20      # Results per page
```

### Following List
**Endpoint:** `GET /api/v1/users/:username/following`  
**Description:** Get users that this user follows  
**Query Parameters:**
```
cursor=123    # Pagination cursor
limit=20      # Results per page
```

### Relationships
**Endpoint:** `PATCH /api/v1/relationships/:id`  
**Description:** Manage relationship with user (follow/mute/block)  
**Payload:**
```json
{
  "follow": true,
  "mute": false,
  "block": false
}
```
**Response:** Updated relationship status

---

## Content & Interactions

### Create Content
**Endpoint:** `POST /api/v1/notes`  
**Description:** Create note, article, or boost  
**Payload (Note):**
```json
{
  "type": "Note",
  "text": "Hello world!",
  "media_ids": ["media_123"],
  "cw": "Optional content warning",
  "visibility": "public"
}
```
**Payload (Boost):**
```json
{
  "type": "Boost",
  "renote_id": "note_456"
}
```
**Payload (Article):**
```json
{
  "type": "Article",
  "title": "My Article",
  "text": "Long form content...",
  "summary": "Optional summary"
}
```

### Get Note
**Endpoint:** `GET /api/v1/notes/:id`  
**Description:** Retrieve specific note  

### Delete Note
**Endpoint:** `DELETE /api/v1/notes/:id`  
**Description:** Delete own note  
**Response:** 204 No Content

### Like Note
**Endpoint:** `POST /api/v1/notes/:id/like`  
**Description:** Like a note  
**Headers:** `Authorization: Bearer <token>`  
**Response:**
```json
{
  "success": true
}
```

### Unlike Note
**Endpoint:** `DELETE /api/v1/notes/:id/like`  
**Description:** Remove like from note  
**Response:** 204 No Content

### Add Reaction
**Endpoint:** `PUT /api/v1/notes/:id/reactions`  
**Description:** Add emoji reaction to note  
**Payload:**
```json
{
  "emoji": "👍"
}
```

### Remove Reaction
**Endpoint:** `DELETE /api/v1/notes/:id/reactions/:emoji`  
**Description:** Remove specific emoji reaction  
**Example:** `DELETE /api/v1/notes/123/reactions/%F0%9F%91%8D` (URL-encoded emoji)

### List Reactions
**Endpoint:** `GET /api/v1/notes/:id/reactions`  
**Description:** Get all reactions on a note  
**Response:**
```json
{
  "reactions": [
    {
      "id": "1",
      "emoji": "👍",
      "account_id": "123",
      "note_id": "456"
    }
  ]
}
```

### Vote on Poll
**Endpoint:** `POST /api/v1/notes/:id/vote`  
**Description:** Submit poll vote (supports multiple choices)  
**Payload:**
```json
{
  "choices": [0, 2]
}
```

---

## Feeds & Real-Time

### Static Feeds
**Endpoint:** `GET /api/v1/feeds/:urn`  
**Description:** Fetch paginated timeline  
**URN Values:**
- `home` - Home timeline (following + self)
- `local` - Local instance timeline
- `public` - Federated timeline

**Query Parameters:**
```
cursor=12345    # Pagination cursor (note ID)
limit=20        # Results per page (default: 20, max: 100)
```

**Response:**
```json
{
  "items": [ /* array of notes */ ],
  "next_cursor": "12340"
}
```

### Streaming
**Endpoint:** `GET /api/v1/streaming/:urn`  
**Description:** Server-Sent Events stream for real-time updates  
**URN Values:** Same as feeds (`home`, `local`, `public`)  
**Content-Type:** `text/event-stream`  
**Event Format:**
```
event: note
data: {"id": "123", "text": "Hello!", ...}

event: delete
data: {"id": "456"}
```

---

## Media & Assets

### Request Upload URL
**Endpoint:** `POST /api/v1/media/presigned`  
**Description:** Get S3 presigned URL for direct upload  
**Payload:**
```json
{
  "filename": "cat.png",
  "mime_type": "image/png",
  "size": 102400
}
```
**Response:**
```json
{
  "upload_url": "https://s3.amazonaws.com/...",
  "s3_key": "user123/uuid.png",
  "expires_at": "2026-03-25T11:29:00Z"
}
```

### Register Media
**Endpoint:** `POST /api/v1/media`  
**Description:** Register uploaded media after S3 upload completes  
**Payload:**
```json
{
  "s3_key": "user123/uuid.png",
  "description": "A cute cat",
  "sensitive": false,
  "blurhash": "LKO2?U%2Tw=w]~RBVZRi};RPxuwH"
}
```
**Response:**
```json
{
  "id": "media_123",
  "url": "https://cdn.example.com/...",
  "thumbnail_url": "https://cdn.example.com/.../thumb.jpg"
}
```

### List Media
**Endpoint:** `GET /api/v1/media`  
**Description:** List user's uploaded media  
**Headers:** `Authorization: Bearer <token>`  
**Query Parameters:**
```
cursor=123    # Pagination cursor
limit=20      # Results per page
```

### List Custom Emojis
**Endpoint:** `GET /api/v1/emojis`  
**Description:** Get instance custom emoji library  
**Response:**
```json
[
  {
    "shortcode": "blobcat",
    "url": "https://cdn.example.com/emojis/blobcat.png",
    "category": "animals"
  }
]
```

---

## Articles

### Create Article
**Endpoint:** `POST /api/v1/articles`  
**Description:** Create long-form article  
**Headers:** `Authorization: Bearer <token>`  
**Payload:**
```json
{
  "title": "My Article",
  "content": "Long form content...",
  "summary": "Optional summary"
}
```

### List Articles
**Endpoint:** `GET /api/v1/articles`  
**Description:** List published articles  
**Query Parameters:**
```
cursor=123    # Pagination cursor
limit=20      # Results per page
```

### Get Article
**Endpoint:** `GET /api/v1/articles/:id`  
**Description:** Get specific article  
**Response:**
```json
{
  "id": "123",
  "title": "My Article",
  "content": "...",
  "summary": "...",
  "published_at": "2026-03-25T10:00:00Z",
  "account_id": "456"
}
```

---

## Utility

### Report Content
**Endpoint:** `POST /api/v1/reports`  
**Description:** Report user or content for moderation  
**Payload:**
```json
{
  "target_id": "user_123",
  "type": "spam",
  "comment": "Posting spam links repeatedly",
  "note_ids": ["note_456", "note_789"]
}
```
**Report Types:** `spam`, `harassment`, `illegal`, `other`

### Bookmarks
**Endpoint:** `GET /api/v1/bookmarks`  
**Description:** List user's saved notes  
**Query Parameters:**
```
cursor=123    # Pagination cursor
limit=20      # Results per page
```

**Endpoint:** `POST /api/v1/bookmarks`  
**Description:** Bookmark a note  
**Payload:**
```json
{
  "note_id": "note_123"
}
```

**Endpoint:** `DELETE /api/v1/bookmarks/:note_id`  
**Description:** Remove bookmark

---

## Admin Endpoints

All admin endpoints require administrative privileges.

### List Reports
**Endpoint:** `GET /api/admin/reports`  
**Description:** List all user reports  

### Resolve Report
**Endpoint:** `POST /api/admin/reports/:id/resolve`  
**Description:** Mark a report as resolved  

### List Instance Blocks
**Endpoint:** `GET /api/admin/instance-blocks`  
**Description:** List all blocked instances  

### Block Instance
**Endpoint:** `POST /api/admin/instance-blocks`  
**Description:** Block federation with a remote domain  
**Payload:**
```json
{
  "domain": "bad-instance.example.com",
  "reason": "Spam instance"
}
```

### Unblock Instance
**Endpoint:** `DELETE /api/admin/instance-blocks/:domain`  
**Description:** Remove block on a remote domain  

### Suspend Account
**Endpoint:** `POST /api/admin/accounts/:id/suspend`  
**Description:** Suspend a local or remote account  

### Unsuspend Account
**Endpoint:** `DELETE /api/admin/accounts/:id/suspend`  
**Description:** Restore a suspended account  

### Create Custom Emoji
**Endpoint:** `POST /api/admin/emojis`  
**Description:** Add a new custom emoji to the instance  
**Payload:**
```json
{
  "shortcode": "blobcat",
  "url": "https://...",
  "category": "animals"
}
```

### Delete Custom Emoji
**Endpoint:** `DELETE /api/admin/emojis/:id`  
**Description:** Remove a custom emoji  

---

## Authentication

All authenticated endpoints require:
```
Authorization: Bearer <token>
```

Obtain token via `POST /api/v1/auth/session`

## Rate Limits

- Anonymous: 100 req/15min
- Authenticated: 300 req/15min
- Media uploads: 10/hour

## Error Responses

```json
{
  "error": "invalid_request",
  "message": "Missing required field: text"
}
```

**Common Status Codes:**
- `400` - Bad Request (invalid payload)
- `401` - Unauthorized (missing/invalid token)
- `403` - Forbidden (insufficient permissions)
- `404` - Not Found
- `422` - Unprocessable Entity (validation error)
- `429` - Too Many Requests (rate limited)
- `500` - Internal Server Error
