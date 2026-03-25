# Real-Time Engine Quick Reference

## 🚀 Quick Start

```bash
# 1. Start the server
cd elixir && iex -S mix

# 2. In another terminal, connect to local feed stream
curl -N http://localhost:4000/api/streaming/local

# 3. In another terminal, create a post
curl -X POST http://localhost:4000/api/notes \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content":"Hello real-time!"}'

# Watch the post appear instantly in terminal 2!
```

## 📡 API Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/api/feeds/home` | GET | ✅ | Paginated home feed |
| `/api/feeds/local` | GET | ❌ | Paginated local feed |
| `/api/streaming/home` | GET | ✅ | Real-time home feed (SSE) |
| `/api/streaming/local` | GET | ❌ | Real-time local feed (SSE) |

## 🔑 Authentication

```bash
# For authenticated endpoints
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:4000/api/feeds/home
```

## 📄 Pagination

```bash
# Get 10 posts
curl "http://localhost:4000/api/feeds/local?limit=10"

# Get next page (posts older than ID 100)
curl "http://localhost:4000/api/feeds/local?limit=10&max_id=100"
```

## 🌊 SSE Event Format

```
event: update
data: {"id":"123","content":"Hello","created_at":"2026-03-25T00:00:00Z"}

:heartbeat

event: update
data: {"id":"124","content":"World","created_at":"2026-03-25T00:00:01Z"}
```

## 🔧 NATS Topic

```elixir
# Publish new post
payload = %{
  object: %{id: 123, content: "Hello"},
  actor_id: "https://example.com/users/alice"
}
Gnat.pub(:gnat, "stream.new_post", Jason.encode!(payload))
```

## 🏗️ Architecture

```
POST /api/notes
    ↓
NotesController
    ↓
NATS (stream.new_post)
    ↓
NatsListener
    ↓
Registry
    ↓
SSE Clients (real-time!)
```

## 🐛 Debugging

```elixir
# Check active SSE connections
:sys.get_state(SukhiFedi.Streaming.Registry)

# Check NATS connection
Gnat.ping(:gnat)

# Test NATS publish manually
Gnat.pub(:gnat, "stream.new_post", ~s({"object":{"id":1},"actor_id":"test"}))
```

## 📊 Monitoring

```elixir
# Count active connections
{:ok, state} = :sys.get_state(SukhiFedi.Streaming.Registry)
map_size(state)

# Check process count
length(Process.list())
```

## 🎯 Common Use Cases

### 1. Display live local timeline
```javascript
const es = new EventSource('http://localhost:4000/api/streaming/local');
es.addEventListener('update', e => {
  const post = JSON.parse(e.data);
  displayPost(post);
});
```

### 2. Load initial posts + stream updates
```javascript
// 1. Load initial posts
const posts = await fetch('/api/feeds/local?limit=20').then(r => r.json());
displayPosts(posts);

// 2. Stream new posts
const es = new EventSource('/api/streaming/local');
es.addEventListener('update', e => {
  const post = JSON.parse(e.data);
  prependPost(post);
});
```

### 3. Infinite scroll with pagination
```javascript
let maxId = null;

async function loadMore() {
  const url = maxId 
    ? `/api/feeds/local?limit=20&max_id=${maxId}`
    : `/api/feeds/local?limit=20`;
  
  const posts = await fetch(url).then(r => r.json());
  if (posts.length > 0) {
    maxId = posts[posts.length - 1].id;
    displayPosts(posts);
  }
}
```

## 🔥 Performance Tips

1. **Connection pooling**: Reuse SSE connections
2. **Pagination**: Use `max_id` for efficient queries
3. **Caching**: Cache follower lists in ETS
4. **Indexing**: Ensure DB indexes on `created_at` and `actor_id`
5. **Heartbeats**: Adjust interval based on network conditions

## 🚨 Troubleshooting

| Problem | Solution |
|---------|----------|
| SSE disconnects | Check firewall/proxy timeouts |
| Posts not appearing | Verify NATS connection |
| High memory | Check for connection leaks |
| Slow queries | Add DB indexes |
| Auth fails | Verify token format |

## 📚 Related Files

- `STREAMING.md` - Full documentation
- `PRIORITY_2_SUMMARY.md` - Implementation details
- `streaming_demo.html` - Browser demo
- `test_streaming.sh` - Test script
