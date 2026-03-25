# Priority 4: The "Misskey Flavor" & Media

**Status:** ✅ COMPLETE

This priority transforms Sukhi Fedi from a generic ActivityPub server into a Misskey-compatible platform with rich media support.

## Features Implemented

### 1. Media Library (S3/R2)

**Presigned URL Upload Flow:**
```bash
# 1. Request upload URL
POST /api/media/upload-url
Authorization: Bearer <token>
{
  "filename": "image.jpg",
  "content_type": "image/jpeg"
}

# Response:
{
  "upload_url": "https://r2.../presigned-url",
  "key": "account_id/random/image.jpg",
  "public_url": "https://cdn.../account_id/random/image.jpg"
}

# 2. Upload directly to S3/R2
PUT <upload_url>
Content-Type: image/jpeg
<binary data>

# 3. Create media record
POST /api/media
{
  "url": "https://cdn.../account_id/random/image.jpg",
  "type": "image",
  "width": 1920,
  "height": 1080,
  "blurhash": "LKO2?U%2Tw=w]~RBVZRi};RPxuwH",
  "description": "Alt text",
  "tags": ["landscape", "sunset"]
}
```

**Environment Variables:**
```bash
S3_BUCKET=sukhi-media
S3_REGION=auto
S3_ENDPOINT=https://account.r2.cloudflarestorage.com
S3_ACCESS_KEY=...
S3_SECRET_KEY=...
S3_PUBLIC_URL=https://cdn.example.com  # Optional CDN
```

**Database Schema:**
```sql
CREATE TABLE media (
  id SERIAL PRIMARY KEY,
  account_id INTEGER NOT NULL,
  url TEXT NOT NULL,
  remote_url TEXT,
  type TEXT NOT NULL,  -- image, video, audio, unknown
  blurhash TEXT,
  description TEXT,
  width INTEGER,
  height INTEGER,
  size INTEGER,
  tags TEXT[],
  created_at TIMESTAMP
);

CREATE TABLE note_media (
  note_id INTEGER REFERENCES notes(id),
  media_id INTEGER REFERENCES media(id)
);
```

### 2. Custom Emojis

**API Endpoints:**
```bash
# List all emojis
GET /api/emojis

# Create emoji (admin)
POST /api/emojis
{
  "shortcode": "blobcat",
  "url": "https://cdn.../emojis/blobcat.png",
  "category": "animals",
  "aliases": ["cat", "kitty"]
}

# Delete emoji
DELETE /api/emojis/:id
```

**Database Schema:**
```sql
CREATE TABLE emojis (
  id SERIAL PRIMARY KEY,
  shortcode TEXT UNIQUE NOT NULL,
  url TEXT NOT NULL,
  category TEXT,
  aliases TEXT[],
  created_at TIMESTAMP
);
```

**Usage in Notes:**
```json
{
  "content": "Hello :blobcat: world!",
  "mfm": "Hello :blobcat: world!"
}
```

### 3. Reactions (Misskey-style)

**API Endpoints:**
```bash
# Add reaction
POST /api/reactions
{
  "note_id": 123,
  "emoji": ":heart:"  # or "❤️"
}

# Remove reaction
DELETE /api/reactions/:id

# List reactions for note
GET /api/reactions/note/:note_id
```

**Database Schema:**
```sql
CREATE TABLE reactions (
  id SERIAL PRIMARY KEY,
  account_id INTEGER NOT NULL,
  note_id INTEGER NOT NULL,
  emoji TEXT NOT NULL,
  ap_id TEXT,
  created_at TIMESTAMP,
  UNIQUE(account_id, note_id, emoji)
);
```

**ActivityPub:**
- Sends `EmojiReact` activities (Misskey extension)
- Falls back to `Like` for compatibility
- Supports custom emoji reactions

### 4. MFM (Misskey Flavored Markdown)

**Supported Syntax:**
```
$[spin text]           - Spinning animation
$[x2 text]            - 2x size
$[blur text]          - Blurred text
$[rainbow text]       - Rainbow colors
$[sparkle text]       - Sparkle effect
$[bounce text]        - Bouncing animation
$[shake text]         - Shaking animation
$[flip text]          - Flipped text

**bold**              - Bold
__italic__            - Italic
~~strikethrough~~     - Strikethrough
`code`                - Inline code
```code block```      - Code block
```

**Sanitization:**
- Strips dangerous HTML (`<script>`, `<iframe>`, `<object>`)
- Validates bracket balancing
- Stores raw MFM in `notes.mfm` field
- Client-side rendering only

**Module:** `SukhiFedi.MFM`
```elixir
# Sanitize MFM input
sanitized = SukhiFedi.MFM.sanitize(user_input)

# Extract plain text for search
plain = SukhiFedi.MFM.to_plain_text(mfm)
```

### 5. Content Warnings (CW)

**Usage:**
```bash
POST /api/notes
{
  "content": "Spoiler content here",
  "cw": "Spoiler warning",
  "visibility": "public"
}
```

**Database:**
```sql
ALTER TABLE notes ADD COLUMN cw TEXT;
```

**ActivityPub:**
- Maps to `summary` field in ActivityStreams
- Federated instances show CW before content

### 6. Polls

**Create Poll:**
```bash
POST /api/notes
{
  "content": "What's your favorite color?",
  "poll": {
    "options": ["Red", "Blue", "Green"],
    "expires_at": "2026-03-26T10:00:00Z",
    "multiple": false
  }
}
```

**Vote:**
```bash
POST /api/polls/vote
{
  "poll_id": 123,
  "option_id": 1
}
```

**Get Results:**
```bash
GET /api/polls/:id

# Response:
{
  "id": 123,
  "expires_at": "2026-03-26T10:00:00Z",
  "multiple": false,
  "options": [
    {"id": 1, "title": "Red", "votes_count": 5},
    {"id": 2, "title": "Blue", "votes_count": 3},
    {"id": 3, "title": "Green", "votes_count": 2}
  ],
  "votes_count": 10
}
```

**Database Schema:**
```sql
CREATE TABLE polls (
  id SERIAL PRIMARY KEY,
  note_id INTEGER UNIQUE NOT NULL,
  expires_at TIMESTAMP,
  multiple BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP
);

CREATE TABLE poll_options (
  id SERIAL PRIMARY KEY,
  poll_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  position INTEGER NOT NULL
);

CREATE TABLE poll_votes (
  id SERIAL PRIMARY KEY,
  account_id INTEGER NOT NULL,
  poll_id INTEGER NOT NULL,
  option_id INTEGER NOT NULL,
  created_at TIMESTAMP,
  UNIQUE(account_id, poll_id, option_id)
);
```

**ActivityPub:**
- Uses `Question` activity type
- Federated poll results
- Supports remote voting

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Client Upload                        │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  1. Request Presigned URL                               │
│     POST /api/media/upload-url                          │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  2. Direct Upload to S3/R2                              │
│     PUT <presigned-url>                                 │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  3. Create Media Record                                 │
│     POST /api/media                                     │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  4. Attach to Note                                      │
│     POST /api/notes {"media_ids": [1, 2]}               │
└─────────────────────────────────────────────────────────┘
```

## Testing

### Media Upload
```bash
# 1. Get upload URL
curl -X POST http://localhost:4000/api/media/upload-url \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.jpg", "content_type": "image/jpeg"}'

# 2. Upload to S3/R2 (use returned upload_url)
curl -X PUT "<upload_url>" \
  -H "Content-Type: image/jpeg" \
  --data-binary @test.jpg

# 3. Create media record
curl -X POST http://localhost:4000/api/media \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"url": "<public_url>", "type": "image", "width": 1920, "height": 1080}'
```

### Custom Emoji
```bash
# Create emoji
curl -X POST http://localhost:4000/api/emojis \
  -H "Content-Type: application/json" \
  -d '{"shortcode": "test", "url": "https://example.com/emoji.png"}'

# List emojis
curl http://localhost:4000/api/emojis
```

### Reactions
```bash
# Add reaction
curl -X POST http://localhost:4000/api/reactions \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"note_id": 1, "emoji": "❤️"}'

# List reactions
curl http://localhost:4000/api/reactions/note/1
```

### MFM Note
```bash
curl -X POST http://localhost:4000/api/notes \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Hello world!",
    "mfm": "$[sparkle Hello] $[rainbow world!]",
    "cw": "Flashy text warning"
  }'
```

### Poll
```bash
# Create poll
curl -X POST http://localhost:4000/api/notes \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Favorite color?",
    "poll": {
      "options": ["Red", "Blue", "Green"],
      "expires_at": "2026-03-26T10:00:00Z",
      "multiple": false
    }
  }'

# Vote
curl -X POST http://localhost:4000/api/polls/vote \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"poll_id": 1, "option_id": 1}'

# Get results
curl http://localhost:4000/api/polls/1
```

## Performance

- **Presigned URLs:** Zero server bandwidth for uploads
- **CDN Integration:** Direct S3/R2 → CDN delivery
- **Indexed Queries:** Fast media library browsing
- **Lazy Loading:** Client-side MFM rendering

## Security

✅ **Presigned URL Expiry:** 15 minutes  
✅ **MFM Sanitization:** XSS prevention  
✅ **Content-Type Validation:** File type checking  
✅ **Size Limits:** Configurable per media type  
⚠️ **Admin-only Emoji Upload:** TODO: Add auth check  
⚠️ **Rate Limiting:** TODO: Prevent spam reactions

## Next Steps

**Priority 5: Moderation & Safety**
- Content filtering
- User blocking
- Report system
- Domain blocking
- Media scanning

**Priority 6: Performance & Scale**
- Media CDN optimization
- Emoji caching
- Reaction aggregation
- Poll result caching
