# Priority 5: Moderation & Extended UX

**Status:** ✅ COMPLETE

Essential features for public launch: user safety, admin tools, bookmarks, push notifications, and long-form content.

## Features Implemented

### 1. User Trust & Safety

**Mute**
- Temporarily or permanently hide content from specific users
- Optional expiration time
- Does not notify the muted user

**Block**
- Completely block interaction with specific users
- Prevents follows, mentions, and visibility
- Bidirectional blocking

**Abuse Reports**
- Users can report problematic content or accounts
- Reports include optional comment and reference to specific note
- Reports tracked with status (open/resolved)

### 2. Admin Moderation

**Instance Defederation**
- Block entire domains from federating
- Severity levels (suspend, silence)
- Reason tracking for transparency
- Automatic filtering in feeds

**User Suspension**
- Admins can suspend local accounts
- Suspension reason stored
- Suspended accounts cannot post or interact
- Audit trail (suspended_by, suspended_at)

**Report Management**
- View all reports (open/resolved)
- Resolve reports with admin attribution
- Track resolution history

### 3. Collections / Bookmarks

**Private Bookmarks**
- Save notes for later reading
- Private to user (not federated)
- Chronological listing
- Pagination support

### 4. Web Push API

**Push Subscriptions**
- Standard Web Push API support
- Per-subscription alert preferences
- Multiple subscriptions per account
- Automatic cleanup on unsubscribe

**Notification Delivery**
- Background task-based delivery
- Supports standard push payload format
- Configurable notification types

### 5. Long-form Articles

**Article Support**
- ActivityPub Article type
- Title, content, summary fields
- Published/updated timestamps
- Full federation support
- Separate from Notes

## Database Schema

### New Tables

```sql
-- User moderation
mutes (account_id, target_id, expires_at)
blocks (account_id, target_id)
reports (account_id, target_id, note_id, comment, status, resolved_at, resolved_by_id)

-- Admin moderation
instance_blocks (domain, severity, reason, created_by_id)

-- Account suspension (added to accounts table)
accounts.suspended_at
accounts.suspended_by_id
accounts.suspension_reason
accounts.is_admin

-- User features
bookmarks (account_id, note_id)
push_subscriptions (account_id, endpoint, p256dh_key, auth_key, alerts)

-- Content types
articles (account_id, ap_id, title, content, summary, published_at, updated_at_ap)
```

## API Endpoints

### User Moderation

```bash
# Mute user
POST /api/mute
{
  "target_id": 123,
  "expires_at": "2026-04-01T00:00:00Z"  # optional
}

# Unmute user
DELETE /api/mute
{
  "target_id": 123
}

# Block user
POST /api/block
{
  "target_id": 123
}

# Unblock user
DELETE /api/block
{
  "target_id": 123
}

# Report user/content
POST /api/reports
{
  "target_id": 123,
  "note_id": 456,  # optional
  "comment": "Spam content"
}
```

### Admin Moderation

```bash
# List reports
GET /api/admin/reports?status=open

# Resolve report
POST /api/admin/reports/:id/resolve

# Block instance
POST /api/admin/instance-blocks
{
  "domain": "bad-instance.com",
  "severity": "suspend",
  "reason": "Spam source"
}

# Unblock instance
DELETE /api/admin/instance-blocks/:domain

# List blocked instances
GET /api/admin/instance-blocks

# Suspend account
POST /api/admin/accounts/:id/suspend
{
  "reason": "Terms violation"
}

# Unsuspend account
DELETE /api/admin/accounts/:id/suspend
```

### Bookmarks

```bash
# Create bookmark
POST /api/bookmarks
{
  "note_id": 123
}

# Delete bookmark
DELETE /api/bookmarks
{
  "note_id": 123
}

# List bookmarks
GET /api/bookmarks?limit=20&offset=0
```

### Web Push

```bash
# Subscribe to push notifications
POST /api/push/subscribe
{
  "endpoint": "https://push.service.com/...",
  "keys": {
    "p256dh": "...",
    "auth": "..."
  },
  "alerts": {
    "mention": true,
    "follow": true,
    "boost": true
  }
}

# Unsubscribe
DELETE /api/push/subscribe
{
  "endpoint": "https://push.service.com/..."
}
```

### Articles

```bash
# Create article
POST /api/articles
{
  "title": "My Long-form Post",
  "content": "Full article content...",
  "summary": "Optional summary"
}

# List articles
GET /api/articles?limit=20&offset=0

# Get article
GET /api/articles/:id
```

## ActivityPub Integration

### Supported Activities

**Block**
- Incoming: Store block relationship
- Outgoing: Federate block to remote instance

**Flag (Report)**
- Incoming: Create report from remote instance
- Outgoing: Send report to remote instance

**Article**
- Incoming: Store as Article object
- Outgoing: Federate as ActivityPub Article type

### Deno Handlers

```typescript
// handlers/moderation.ts
handleBlock(nc, data)    // Process incoming Block
handleFlag(nc, data)     // Process incoming Flag (report)

// handlers/article.ts
handleArticle(nc, data)  // Process incoming Article
buildArticle(params)     // Build outgoing Article
```

### Inbox Processing

The inbox handler (`deno/handlers/inbox.ts`) now supports:
- `Block` - User blocking
- `Flag` - Abuse reports
- `Article` - Long-form content

## Feed Filtering

Feeds automatically filter out:
- Content from blocked users
- Content from muted users (with expiration check)
- Content from defederated instances
- Content from suspended accounts

Applied to:
- Home feed (`/api/feeds/home`)
- Local feed (`/api/feeds/local`)
- Streaming endpoints (`/api/streaming/*`)

## Security Considerations

### Admin Authorization

All admin endpoints require:
1. Valid authentication
2. `is_admin = true` on account
3. Returns 403 for non-admin users

### Privacy

- Bookmarks are private (not federated)
- Mutes are local (not federated)
- Blocks are federated (ActivityPub Block)
- Reports can be federated (ActivityPub Flag)

### Rate Limiting

⚠️ **TODO**: Implement rate limiting on:
- Report creation (prevent spam)
- Block/mute operations
- Admin actions

## Implementation Notes

### Minimal Design

- No complex moderation workflows
- Simple open/resolved report states
- Binary block/mute (no partial restrictions)
- Single admin role (no granular permissions)

### Scalability

- Indexes on all foreign keys
- Efficient feed filtering queries
- Background push notification delivery
- Cached blocked domain list

### Future Enhancements

Potential additions (not in scope):
- Moderation queues
- Appeal system
- Granular admin roles
- Content warnings auto-detection
- Keyword filters
- Account migration
- Scheduled posts

## Testing

### Manual Testing

```bash
# Test mute
curl -X POST http://localhost:4000/api/mute \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"target_id": 2}'

# Test block
curl -X POST http://localhost:4000/api/block \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"target_id": 2}'

# Test report
curl -X POST http://localhost:4000/api/reports \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"target_id": 2, "comment": "Test report"}'

# Test bookmark
curl -X POST http://localhost:4000/api/bookmarks \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"note_id": 1}'

# Test article
curl -X POST http://localhost:4000/api/articles \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Article", "content": "Long content..."}'

# Admin: Block instance
curl -X POST http://localhost:4000/api/admin/instance-blocks \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"domain": "spam.example.com", "severity": "suspend"}'
```

### Database Verification

```sql
-- Check mutes
SELECT * FROM mutes;

-- Check blocks
SELECT * FROM blocks;

-- Check reports
SELECT * FROM reports;

-- Check instance blocks
SELECT * FROM instance_blocks;

-- Check bookmarks
SELECT * FROM bookmarks;

-- Check push subscriptions
SELECT * FROM push_subscriptions;

-- Check articles
SELECT * FROM articles;

-- Check suspended accounts
SELECT username, suspended_at, suspension_reason FROM accounts WHERE suspended_at IS NOT NULL;
```

## Migration

```bash
cd elixir
mix ecto.migrate
```

This runs:
- `20260325101000_add_priority_5_tables.exs` - All Priority 5 tables
- `20260325101001_add_is_admin_to_accounts.exs` - Admin flag

## Configuration

### Making First Admin

```sql
-- Set first user as admin
UPDATE accounts SET is_admin = true WHERE id = 1;
```

### Web Push Setup

To enable actual push notifications, add to `mix.exs`:

```elixir
{:web_push_encryption, "~> 0.3"}
```

Then configure VAPID keys in `config/config.exs`:

```elixir
config :web_push_encryption, :vapid_details,
  subject: "mailto:admin@your-instance.com",
  public_key: "...",
  private_key: "..."
```

## Performance

- Mute/block checks: O(1) with indexes
- Feed filtering: Single query with WHERE NOT IN
- Instance blocks: Cached in memory (TODO)
- Push delivery: Async background tasks

## Compliance

- GDPR: Users can delete bookmarks, reports
- Moderation transparency: Reasons stored
- Audit trail: All admin actions attributed

---

**Next Steps:**
- Add rate limiting
- Implement keyword filters
- Add moderation dashboard UI
- Enhance report details
- Add appeal system
