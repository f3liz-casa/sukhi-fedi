# Removed/Changed Endpoints Analysis

## ❌ Removed Endpoints

### 1. **Separate Like/Boost/Undo Endpoints**
**Old:**
- `POST /api/likes` - Like a post
- `POST /api/boosts` - Boost a post  
- `POST /api/undo` - Undo an activity

**Status:** ❌ **REMOVED**

**Impact:** These were separate endpoints for creating specific activity types.

**Replacement:** Now unified in `POST /api/v1/notes` with `type` field:
```json
// Like - NOT IMPLEMENTED in new version
{"type": "Like", "object_id": "note_123"}

// Boost
{"type": "Boost", "renote_id": "note_123"}

// Undo - NOT IMPLEMENTED in new version
{"type": "Undo", "activity_id": "activity_123"}
```

**⚠️ MISSING:** Like and Undo functionality not implemented in new NotesController

---

### 2. **Separate Mute/Block Endpoints**
**Old:**
- `POST /api/mute` - Mute user
- `DELETE /api/mute` - Unmute user
- `POST /api/block` - Block user
- `DELETE /api/block` - Unblock user

**Status:** ✅ **REPLACED**

**Replacement:** `PATCH /api/v1/relationships/:id`
```json
{"mute": true}  // or {"block": true}
```

---

### 3. **Separate Follow/Unfollow Endpoints**
**Old:**
- `POST /api/follow`
- `POST /api/unfollow`

**Status:** ✅ **REPLACED**

**Replacement:** `PATCH /api/v1/relationships/:id`
```json
{"follow": true}  // or {"follow": false}
```

---

### 4. **Account Registration**
**Old:**
- `POST /api/accounts` - Create new account
- `POST /api/tokens` - Get auth token

**Status:** ❌ **REMOVED**

**Impact:** No way to register new accounts in v1 API

**⚠️ MISSING:** Account registration endpoint

---

### 5. **Articles**
**Old:**
- `POST /api/articles` - Create article
- `GET /api/articles` - List articles
- `GET /api/articles/:id` - Get article

**Status:** ❌ **REMOVED** (but partially supported)

**Replacement:** `POST /api/v1/notes` with `type: "Article"`
```json
{
  "type": "Article",
  "title": "My Article",
  "text": "Content...",
  "summary": "Summary..."
}
```

**⚠️ MISSING:** Dedicated article listing endpoint (`GET /api/v1/articles`)

---

### 6. **Profile Update**
**Old:**
- `PUT /api/profile` - Update own profile

**Status:** ❌ **REMOVED**

**Impact:** No way to update display name, bio, avatar, etc.

**⚠️ MISSING:** Profile update endpoint

---

### 7. **User Notes Listing**
**Old:**
- `GET /api/users/:username/notes` - List user's notes

**Status:** ❌ **REMOVED**

**Impact:** Cannot fetch a specific user's timeline

**⚠️ MISSING:** User timeline endpoint

---

### 8. **Followers List**
**Old:**
- `GET /api/users/:username/followers` - List followers

**Status:** ❌ **REMOVED**

**Impact:** Cannot view who follows a user

**⚠️ MISSING:** Followers/following list endpoints

---

### 9. **OAuth Callback**
**Old:**
- `GET /auth/:provider/callback` - OAuth provider callback

**Status:** ❌ **REMOVED**

**Impact:** No OAuth authentication support

**⚠️ MISSING:** OAuth integration

---

### 10. **Push Notifications**
**Old:**
- `POST /api/push/subscribe` - Subscribe to push
- `DELETE /api/push/subscribe` - Unsubscribe

**Status:** ❌ **REMOVED**

**Impact:** No web push notification support

**⚠️ MISSING:** Push notification endpoints

---

### 11. **Legacy ActivityPub Endpoints**
**Old:**
- `POST /api/notes/cw` - Create note with content warning
- `POST /api/reacts` - React to note
- `POST /api/quotes` - Quote note
- `POST /api/polls` - Create poll

**Status:** ✅ **REPLACED/INTEGRATED**

**Replacement:** All handled by `POST /api/v1/notes` with appropriate fields

---

### 12. **Media Listing**
**Old:**
- `GET /api/media` - List user's media

**Status:** ❌ **REMOVED**

**Impact:** Cannot browse uploaded media library

**⚠️ MISSING:** Media library listing

---

### 13. **Poll Details**
**Old:**
- `GET /api/polls/:id` - Get poll results

**Status:** ❌ **REMOVED**

**Impact:** Cannot fetch poll results separately from note

**⚠️ MISSING:** Standalone poll endpoint (polls should be embedded in note response)

---

### 14. **Reaction Listing**
**Old:**
- `GET /api/reactions/note/:note_id` - List reactions on note

**Status:** ❌ **REMOVED**

**Impact:** Cannot fetch all reactions on a note

**⚠️ MISSING:** Reaction listing endpoint

---

## 🔴 Critical Missing Functionality

### High Priority (Core Features)
1. **Account Registration** - `POST /api/v1/accounts`
2. **Like Activity** - Should be in `POST /api/v1/notes` or separate endpoint
3. **Undo Activity** - `POST /api/v1/notes/:id/undo` or similar
4. **Profile Update** - `PATCH /api/v1/me`
5. **User Timeline** - `GET /api/v1/users/:username/notes`

### Medium Priority (Social Features)
6. **Followers/Following Lists** - `GET /api/v1/users/:username/followers`
7. **Reaction Listing** - `GET /api/v1/notes/:id/reactions`
8. **Media Library** - `GET /api/v1/media`

### Low Priority (Extended Features)
9. **Articles Listing** - `GET /api/v1/articles`
10. **Push Notifications** - `POST /api/v1/push/subscribe`
11. **OAuth Support** - `GET /auth/:provider/callback`
12. **Poll Details** - Should be embedded in note response

---

## ✅ Properly Migrated

- WebFinger
- ActivityPub inbox/outbox
- Authentication (unified)
- Feeds (URN-based)
- Streaming (URN-based)
- Reactions (add/remove)
- Poll voting
- Bookmarks
- Reports
- Admin endpoints
- Custom emojis

---

## 📋 Recommendation

**Restore these endpoints:**

1. `POST /api/v1/accounts` - Account registration
2. `PATCH /api/v1/me` - Profile update
3. `GET /api/v1/users/:username/notes` - User timeline
4. `GET /api/v1/users/:username/followers` - Followers list
5. `GET /api/v1/users/:username/following` - Following list
6. `POST /api/v1/notes/:id/like` - Like a note
7. `DELETE /api/v1/notes/:id/like` - Unlike a note
8. `POST /api/v1/notes/:id/undo` - Undo activity
9. `GET /api/v1/notes/:id/reactions` - List reactions
10. `GET /api/v1/media` - List user's media
11. `GET /api/v1/articles` - List articles
12. `GET /api/v1/articles/:id` - Get article

**Optional (if needed):**
- Push notification endpoints
- OAuth endpoints
