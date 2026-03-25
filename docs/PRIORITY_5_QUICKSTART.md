# Priority 5 Quick Start Guide

## Setup (5 minutes)

### 1. Run Migrations
```bash
cd elixir
mix ecto.migrate
```

This creates:
- `mutes`, `blocks`, `reports` tables
- `instance_blocks` table
- `bookmarks` table
- `push_subscriptions` table
- `articles` table
- Adds `is_admin`, `suspended_at` to `accounts`

### 2. Create First Admin
```bash
# In psql or your DB client
psql -U postgres -d sukhi_fedi -c "UPDATE accounts SET is_admin = true WHERE id = 1;"
```

### 3. Test Endpoints
```bash
cd docs
./test_priority5.sh
```

## Usage Examples

### User Moderation

#### Mute a User
```bash
curl -X POST http://localhost:4000/api/mute \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "target_id": 2,
    "expires_at": "2026-04-01T00:00:00Z"
  }'
```

#### Block a User
```bash
curl -X POST http://localhost:4000/api/block \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"target_id": 3}'
```

#### Report Abuse
```bash
curl -X POST http://localhost:4000/api/reports \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "target_id": 2,
    "note_id": 123,
    "comment": "Spam content"
  }'
```

### Bookmarks

#### Save a Note
```bash
curl -X POST http://localhost:4000/api/bookmarks \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"note_id": 123}'
```

#### List Bookmarks
```bash
curl -X GET "http://localhost:4000/api/bookmarks?limit=20" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Articles

#### Create Article
```bash
curl -X POST http://localhost:4000/api/articles \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "My First Article",
    "content": "This is a long-form article with multiple paragraphs...",
    "summary": "A brief summary"
  }'
```

#### List Articles
```bash
curl -X GET "http://localhost:4000/api/articles?limit=20"
```

### Admin Actions

#### View Reports
```bash
curl -X GET "http://localhost:4000/api/admin/reports?status=open" \
  -H "Authorization: Bearer ADMIN_TOKEN"
```

#### Resolve Report
```bash
curl -X POST http://localhost:4000/api/admin/reports/1/resolve \
  -H "Authorization: Bearer ADMIN_TOKEN"
```

#### Block Instance
```bash
curl -X POST http://localhost:4000/api/admin/instance-blocks \
  -H "Authorization: Bearer ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "spam.example.com",
    "severity": "suspend",
    "reason": "Spam source"
  }'
```

#### Suspend User
```bash
curl -X POST http://localhost:4000/api/admin/accounts/2/suspend \
  -H "Authorization: Bearer ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reason": "Terms violation"}'
```

### Web Push

#### Subscribe to Notifications
```bash
curl -X POST http://localhost:4000/api/push/subscribe \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "endpoint": "https://push.service.com/...",
    "keys": {
      "p256dh": "BASE64_KEY",
      "auth": "BASE64_KEY"
    },
    "alerts": {
      "mention": true,
      "follow": true,
      "boost": true
    }
  }'
```

## Database Queries

### Check Mutes
```sql
SELECT a1.username as muter, a2.username as muted, m.expires_at
FROM mutes m
JOIN accounts a1 ON m.account_id = a1.id
JOIN accounts a2 ON m.target_id = a2.id;
```

### Check Blocks
```sql
SELECT a1.username as blocker, a2.username as blocked
FROM blocks b
JOIN accounts a1 ON b.account_id = a1.id
JOIN accounts a2 ON b.target_id = a2.id;
```

### Check Reports
```sql
SELECT 
  r.id,
  a1.username as reporter,
  a2.username as target,
  r.comment,
  r.status,
  r.created_at
FROM reports r
LEFT JOIN accounts a1 ON r.account_id = a1.id
JOIN accounts a2 ON r.target_id = a2.id
ORDER BY r.created_at DESC;
```

### Check Instance Blocks
```sql
SELECT domain, severity, reason, created_at
FROM instance_blocks
ORDER BY created_at DESC;
```

### Check Suspended Accounts
```sql
SELECT 
  a.username,
  a.suspended_at,
  a.suspension_reason,
  admin.username as suspended_by
FROM accounts a
LEFT JOIN accounts admin ON a.suspended_by_id = admin.id
WHERE a.suspended_at IS NOT NULL;
```

### Check Bookmarks
```sql
SELECT a.username, n.content, b.created_at
FROM bookmarks b
JOIN accounts a ON b.account_id = a.id
JOIN notes n ON b.note_id = n.id
ORDER BY b.created_at DESC;
```

## Verification

### Test Feed Filtering
```bash
# Block a user
curl -X POST http://localhost:4000/api/block \
  -H "Authorization: Bearer TOKEN1" \
  -d '{"target_id": 2}'

# Check home feed - should not see user 2's posts
curl -X GET http://localhost:4000/api/feeds/home \
  -H "Authorization: Bearer TOKEN1"
```

### Test Admin Authorization
```bash
# Try admin endpoint without admin flag (should fail)
curl -X GET http://localhost:4000/api/admin/reports \
  -H "Authorization: Bearer NON_ADMIN_TOKEN"

# Should return 403 Forbidden
```

### Test Article Federation
```bash
# Create article
curl -X POST http://localhost:4000/api/articles \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "title": "Test",
    "content": "Content"
  }'

# Check it appears in outbox
curl -X GET http://localhost:4000/users/USERNAME/outbox
```

## Common Issues

### "unauthorized" Error
- Check your Bearer token is valid
- Verify token in Authorization header: `Bearer YOUR_TOKEN`

### "403 Forbidden" on Admin Endpoints
- Ensure account has `is_admin = true`
- Check: `SELECT is_admin FROM accounts WHERE id = YOUR_ID;`

### Feed Not Filtering Blocked Users
- Verify block exists: `SELECT * FROM blocks WHERE account_id = YOUR_ID;`
- Check feed query includes account_id parameter

### Articles Not Federating
- Ensure Deno worker is running
- Check NATS connection
- Verify Article handler in inbox.ts

## Configuration

### Enable Web Push (Optional)
Add to `mix.exs`:
```elixir
{:web_push_encryption, "~> 0.3"}
```

Add to `config/config.exs`:
```elixir
config :web_push_encryption, :vapid_details,
  subject: "mailto:admin@your-instance.com",
  public_key: "YOUR_PUBLIC_KEY",
  private_key: "YOUR_PRIVATE_KEY"
```

Generate VAPID keys:
```bash
npx web-push generate-vapid-keys
```

## Monitoring

### Check Report Count
```sql
SELECT status, COUNT(*) FROM reports GROUP BY status;
```

### Check Instance Blocks
```sql
SELECT COUNT(*) FROM instance_blocks;
```

### Check Active Mutes
```sql
SELECT COUNT(*) FROM mutes 
WHERE expires_at IS NULL OR expires_at > NOW();
```

### Check Bookmark Usage
```sql
SELECT account_id, COUNT(*) as bookmark_count
FROM bookmarks
GROUP BY account_id
ORDER BY bookmark_count DESC
LIMIT 10;
```

## Next Steps

1. ✅ Test all endpoints with `./test_priority5.sh`
2. ✅ Create admin account
3. ✅ Test moderation features
4. ✅ Verify feed filtering works
5. ⚙️ Configure Web Push (optional)
6. 🚀 Deploy to production

## Documentation

- Full guide: `docs/PRIORITY_5_MODERATION.md`
- Checklist: `docs/PRIORITY_5_CHECKLIST.md`
- Complete summary: `docs/PRIORITY_5_COMPLETE.md`
- Architecture: `docs/COMPLETE_ARCHITECTURE.md`

---

**Ready to launch!** 🚀
