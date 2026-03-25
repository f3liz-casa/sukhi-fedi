# Federation Deployment Guide

## Prerequisites

- ✅ Elixir server running
- ✅ Deno worker running
- ✅ NATS server running
- ✅ PostgreSQL database
- ⚠️ **HTTPS enabled** (required for federation)
- ⚠️ **Valid domain name** (required for federation)

## Step 1: Configure Domain

```elixir
# config/config.exs
config :sukhi_fedi,
  domain: "your.domain.com"  # NO http:// or https://
```

This domain will be used for:
- Actor URIs: `https://your.domain.com/users/alice`
- Inbox URLs: `https://your.domain.com/users/alice/inbox`
- WebFinger: `acct:alice@your.domain.com`

## Step 2: Set Up HTTPS

Federation **requires** HTTPS. Options:

### Option A: Nginx Reverse Proxy
```nginx
server {
    listen 443 ssl http2;
    server_name your.domain.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Option B: Caddy (automatic HTTPS)
```
your.domain.com {
    reverse_proxy localhost:4000
}
```

### Option C: Let's Encrypt + Certbot
```bash
certbot certonly --standalone -d your.domain.com
```

## Step 3: Run Migrations

```bash
cd elixir
mix ecto.migrate
```

Verify tables exist:
```sql
\dt
-- Should show: accounts, objects, follows, oban_jobs, etc.
```

## Step 4: Start Services

### Terminal 1: NATS
```bash
docker run -p 4222:4222 nats:latest
```

### Terminal 2: PostgreSQL
```bash
docker run -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:latest
```

### Terminal 3: Deno Worker
```bash
cd deno
export NATS_URL="nats://localhost:4222"
deno run --allow-net --allow-env main.ts
```

### Terminal 4: Elixir Server
```bash
cd elixir
export DATABASE_URL="postgresql://postgres:postgres@localhost/sukhi_fedi"
export NATS_URL="nats://localhost:4222"
iex -S mix
```

## Step 5: Create Test Account

```bash
curl -X POST https://your.domain.com/api/accounts \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","display_name":"Alice","summary":"Test account"}'
```

## Step 6: Verify Federation Endpoints

### WebFinger
```bash
curl "https://your.domain.com/.well-known/webfinger?resource=acct:alice@your.domain.com"
```

Expected response:
```json
{
  "subject": "acct:alice@your.domain.com",
  "links": [
    {
      "rel": "self",
      "type": "application/activity+json",
      "href": "https://your.domain.com/users/alice"
    }
  ]
}
```

### Actor Profile
```bash
curl -H "Accept: application/activity+json" \
  https://your.domain.com/users/alice
```

Expected response:
```json
{
  "@context": ["https://www.w3.org/ns/activitystreams", ...],
  "id": "https://your.domain.com/users/alice",
  "type": "Person",
  "preferredUsername": "alice",
  ...
}
```

### Outbox
```bash
curl -H "Accept: application/activity+json" \
  https://your.domain.com/users/alice/outbox
```

## Step 7: Test with Real Instance

### From Mastodon

1. Go to your Mastodon instance
2. Search for: `@alice@your.domain.com`
3. Click "Follow"

### Verify on Your Instance

```sql
-- Check if follow was received
SELECT * FROM follows;

-- Check if Accept was sent
SELECT * FROM oban_jobs WHERE queue = 'delivery';
```

### Check Logs

```elixir
# In IEx
Oban.check_queue(queue: :delivery)
```

## Step 8: Test Outgoing Activities

### Create Token
```bash
TOKEN=$(curl -s -X POST https://your.domain.com/api/tokens \
  -H "Content-Type: application/json" \
  -d '{"username":"alice"}' | jq -r '.token')
```

### Create Post
```bash
curl -X POST https://your.domain.com/api/notes \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$TOKEN\",\"content\":\"Hello Fediverse!\"}"
```

### Like Remote Post
```bash
curl -X POST https://your.domain.com/api/likes \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$TOKEN\",\"object\":\"https://mastodon.social/users/someone/statuses/123\"}"
```

## Monitoring

### Check Oban Queue Health

```elixir
# In IEx
Oban.check_queue(queue: :delivery)
```

### Check Failed Jobs

```sql
SELECT id, args, errors, state, attempted_at 
FROM oban_jobs 
WHERE state IN ('retryable', 'discarded')
ORDER BY attempted_at DESC 
LIMIT 10;
```

### Check Recent Activities

```sql
SELECT id, type, actor_id, created_at 
FROM objects 
ORDER BY created_at DESC 
LIMIT 20;
```

### Monitor Delivery Success Rate

```sql
SELECT 
  state,
  COUNT(*) as count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) as percentage
FROM oban_jobs
WHERE queue = 'delivery'
GROUP BY state;
```

## Troubleshooting

### Issue: "Signature verification failed"

**Cause:** Remote server can't verify your signatures

**Solutions:**
1. Ensure HTTPS is enabled
2. Check server time (clock skew)
3. Verify public key is accessible at `/users/:name`

### Issue: "Deliveries stuck in queue"

**Cause:** Oban not processing jobs

**Solutions:**
```elixir
# Check if Oban is running
Oban.check_queue(queue: :delivery)

# Manually drain queue (testing only)
Oban.drain_queue(queue: :delivery)

# Check worker errors
Oban.drain_queue(queue: :delivery, with_safety: false)
```

### Issue: "Remote server not receiving activities"

**Cause:** Incorrect inbox URL or signature

**Solutions:**
1. Check Oban job errors:
   ```sql
   SELECT args, errors FROM oban_jobs WHERE state = 'retryable';
   ```
2. Verify inbox URL is correct
3. Check remote server logs

### Issue: "WebFinger not working"

**Cause:** Domain mismatch or HTTPS issue

**Solutions:**
1. Verify domain in config matches actual domain
2. Ensure HTTPS is working
3. Check WebFinger response format

## Performance Tuning

### For Small Instances (<100 users)

```elixir
# config/config.exs
config :sukhi_fedi, Oban,
  repo: SukhiFedi.Repo,
  queues: [delivery: 10]
```

### For Medium Instances (100-1000 users)

```elixir
config :sukhi_fedi, Oban,
  repo: SukhiFedi.Repo,
  queues: [delivery: 50]
```

### For Large Instances (>1000 users)

```elixir
config :sukhi_fedi, Oban,
  repo: SukhiFedi.Repo,
  queues: [delivery: 100]
```

### Database Indexes

Ensure these indexes exist:
```sql
CREATE INDEX CONCURRENTLY idx_objects_actor_created 
  ON objects (actor_id, created_at DESC);

CREATE INDEX CONCURRENTLY idx_objects_type 
  ON objects (type);

CREATE INDEX CONCURRENTLY idx_follows_followee_state 
  ON follows (followee_id, state);
```

## Security Checklist

- [x] HTTPS enabled
- [x] HTTP Signature verification enabled
- [ ] Rate limiting on inbox (TODO)
- [ ] Domain blocking (TODO)
- [ ] Content filtering (TODO)
- [ ] Firewall rules configured
- [ ] Monitoring alerts set up

## Production Checklist

- [ ] HTTPS configured and working
- [ ] Domain name configured correctly
- [ ] All migrations run
- [ ] Oban queue configured
- [ ] Database indexes created
- [ ] Monitoring set up
- [ ] Backups configured
- [ ] Tested with real Mastodon instance
- [ ] Tested with real Misskey instance
- [ ] Logs being collected
- [ ] Alerts configured

## Next Steps

1. **Test thoroughly** with real instances
2. **Monitor** Oban queue and delivery success rate
3. **Add rate limiting** to prevent abuse
4. **Implement domain blocking** if needed
5. **Set up monitoring alerts** for queue depth
6. **Configure backups** for database

## Support

- Check logs in IEx
- Query Oban jobs table
- Check NATS connection: `Gnat.ping(:gnat)`
- Review PRIORITY_3_FEDERATION.md for details

## License

All code is licensed under MPL-2.0.
