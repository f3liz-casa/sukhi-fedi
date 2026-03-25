# Priority 3: Federation Quick Reference

## Endpoints

### ActivityPub Core
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/.well-known/webfinger?resource=acct:user@domain` | Actor discovery |
| GET | `/users/:name` | Actor profile (JSON-LD) |
| GET | `/users/:name/outbox` | Actor's public activities |
| POST | `/users/:name/inbox` | Receive activities for user |
| POST | `/inbox` | Shared inbox for all users |

### Outgoing Activities
| Method | Endpoint | Body | Description |
|--------|----------|------|-------------|
| POST | `/api/likes` | `{token, object}` | Like a post |
| POST | `/api/boosts` | `{token, object}` | Boost/announce a post |
| POST | `/api/undo` | `{token, object}` | Undo an activity |
| POST | `/api/notes` | `{token, content}` | Create a post |
| POST | `/api/reacts` | `{token, object, emoji}` | React with emoji |

## NATS Topics

| Topic | Handler | Purpose |
|-------|---------|---------|
| `ap.verify` | `verify.ts` | HTTP signature verification |
| `ap.inbox` | `inbox.ts` | Process incoming activities |
| `ap.build.like` | `like.ts` | Build Like activity |
| `ap.build.undo` | `undo.ts` | Build Undo activity |
| `ap.build.announce` | `boost.ts` | Build Announce activity |

## Supported Incoming Activities

- ✅ Follow → Auto-accept
- ✅ Create → Store post
- ✅ Update → Update post
- ✅ Delete → Remove post
- ✅ Like → Store like
- ✅ Announce → Store boost
- ✅ Undo → Reverse action
- ✅ Accept/Reject → Follow responses
- ✅ EmojiReact → Misskey reactions
- ✅ Move → Account migration
- ✅ Block → Blocking
- ✅ Flag → Reports

## Database Tables

### objects
```sql
id | ap_id | type | actor_id | raw_json | created_at
```

### follows
```sql
id | follower_uri | followee_id | state | created_at
```

### oban_jobs
```sql
id | queue | state | args | errors | attempted_at
```

## Common Tasks

### Check Oban Queue
```elixir
# In IEx
Oban.check_queue(queue: :delivery)
```

### Drain Queue (Testing)
```elixir
Oban.drain_queue(queue: :delivery)
```

### Check Failed Jobs
```sql
SELECT id, args, errors, state 
FROM oban_jobs 
WHERE state IN ('retryable', 'discarded')
ORDER BY attempted_at DESC;
```

### Check Recent Activities
```sql
SELECT id, type, actor_id, created_at 
FROM objects 
ORDER BY created_at DESC 
LIMIT 20;
```

### Check Follows
```sql
SELECT follower_uri, followee_id, state 
FROM follows 
ORDER BY created_at DESC;
```

## Testing Flow

1. **Create account**: `POST /api/accounts`
2. **Get token**: `POST /api/tokens`
3. **Test WebFinger**: `GET /.well-known/webfinger?resource=acct:user@domain`
4. **Test Actor**: `GET /users/:name` with `Accept: application/activity+json`
5. **Create post**: `POST /api/notes`
6. **Like remote post**: `POST /api/likes`
7. **Check queue**: `SELECT * FROM oban_jobs;`

## Debugging

### Enable Verbose Logging
```elixir
# config/dev.exs
config :logger, level: :debug
```

### Check NATS Connection
```elixir
Gnat.ping(:gnat)
```

### Test NATS Request
```elixir
payload = Jason.encode!(%{request_id: "test", payload: %{raw: %{}}})
{:ok, msg} = Gnat.request(:gnat, "ap.inbox", payload)
Jason.decode!(msg.body)
```

## Performance Tips

- Increase Oban workers for high-traffic instances
- Add database indexes on frequently queried columns
- Monitor Oban queue depth
- Use connection pooling for HTTP requests

## Security Checklist

- ✅ HTTP Signature verification enabled
- ⚠️ Rate limiting (TODO)
- ⚠️ Content filtering (TODO)
- ⚠️ Domain blocking (TODO)

## Next Steps

1. Test with real Mastodon instance
2. Test with real Misskey instance
3. Monitor Oban queue performance
4. Add rate limiting
5. Implement followers/following collections
6. Add media attachment support
