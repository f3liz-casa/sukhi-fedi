# Real-Time Engine Documentation

## Overview

The real-time engine enables instant delivery of posts to connected clients using Server-Sent Events (SSE) and NATS as an internal message broker.

## Architecture

```
Post Creation → NATS (stream.new_post) → NatsListener → Registry → SSE Clients
```

### Components

1. **Feeds Module** (`SukhiFedi.Feeds`)
   - Queries home and local feeds from PostgreSQL
   - Supports pagination with `limit` and `max_id`

2. **Streaming Registry** (`SukhiFedi.Streaming.Registry`)
   - Manages SSE connection subscriptions
   - Routes events to appropriate subscribers
   - Automatically cleans up disconnected clients

3. **NATS Listener** (`SukhiFedi.Streaming.NatsListener`)
   - Subscribes to `stream.new_post` topic
   - Broadcasts to local feed (if local actor)
   - Broadcasts to home feeds of followers

4. **Controllers**
   - `FeedsController`: HTTP endpoints for feed pagination
   - `StreamingController`: SSE endpoints for real-time updates

## API Endpoints

### HTTP Feed Endpoints

#### GET /api/feeds/home
Get paginated home feed (requires authentication).

**Headers:**
- `Authorization: Bearer <token>`

**Query Parameters:**
- `limit` (optional, default: 20): Number of posts to return
- `max_id` (optional): Return posts older than this ID

**Response:**
```json
[
  {
    "id": "123",
    "ap_id": "https://...",
    "type": "Note",
    "actor_id": "https://...",
    "raw_json": {...},
    "created_at": "2026-03-25T00:00:00Z"
  }
]
```

#### GET /api/feeds/local
Get paginated local feed (public).

**Query Parameters:**
- `limit` (optional, default: 20)
- `max_id` (optional)

**Response:** Same as home feed

### SSE Streaming Endpoints

#### GET /api/streaming/home
Real-time home feed updates (requires authentication).

**Headers:**
- `Authorization: Bearer <token>`

**Response:** SSE stream
```
event: update
data: {"id":"123","content":"..."}

:heartbeat

event: update
data: {"id":"124","content":"..."}
```

#### GET /api/streaming/local
Real-time local feed updates (public).

**Response:** SSE stream (same format as home)

## NATS Topics

### stream.new_post
Published when a new post is created.

**Payload:**
```json
{
  "object": {
    "id": "123",
    "content": "Hello world",
    "created_at": "2026-03-25T00:00:00Z"
  },
  "actor_id": "https://example.com/users/alice"
}
```

## Usage Examples

### Fetch Home Feed (HTTP)
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:4000/api/feeds/home?limit=10"
```

### Fetch Local Feed (HTTP)
```bash
curl "http://localhost:4000/api/feeds/local?limit=20&max_id=100"
```

### Stream Home Feed (SSE)
```bash
curl -N -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:4000/api/streaming/home"
```

### Stream Local Feed (SSE)
```bash
curl -N "http://localhost:4000/api/streaming/local"
```

### JavaScript Client Example
```javascript
const token = 'YOUR_TOKEN';
const eventSource = new EventSource(
  'http://localhost:4000/api/streaming/home',
  {
    headers: {
      'Authorization': `Bearer ${token}`
    }
  }
);

eventSource.addEventListener('update', (event) => {
  const post = JSON.parse(event.data);
  console.log('New post:', post);
});

eventSource.onerror = (error) => {
  console.error('SSE error:', error);
};
```

## Flow Diagram

### Post Creation Flow
```
1. User creates post via POST /api/notes
2. NotesController saves to DB
3. NotesController publishes to NATS (stream.new_post)
4. NatsListener receives message
5. NatsListener determines recipients:
   - Local feed: if actor is local
   - Home feeds: followers of the actor
6. NatsListener broadcasts to Registry
7. Registry sends to connected SSE clients
8. Clients receive real-time update
```

### SSE Connection Flow
```
1. Client connects to /api/streaming/home or /api/streaming/local
2. StreamingController authenticates (if home feed)
3. StreamingController subscribes to Registry
4. StreamingController sends initial heartbeat
5. StreamingController enters event loop:
   - Receives events from Registry
   - Formats as SSE
   - Sends to client
   - Sends heartbeat every 15s
6. On disconnect, Registry automatically cleans up
```

## Performance Considerations

- **Heartbeats**: Sent every 15 seconds to keep connections alive
- **Connection Limits**: No hard limit, but monitor system resources
- **Message Size**: Keep post payloads minimal for SSE efficiency
- **NATS**: Single broker sufficient for most deployments
- **Scaling**: Add more Elixir nodes for horizontal scaling

## Monitoring

Key metrics to monitor:
- Active SSE connections (Registry state)
- NATS message throughput
- Feed query performance
- Memory usage (Registry + connections)

## Troubleshooting

### SSE connections drop frequently
- Check firewall/proxy timeout settings
- Increase heartbeat frequency if needed
- Verify network stability

### Posts not appearing in real-time
- Check NATS connection status
- Verify NatsListener is running
- Check Registry subscriptions
- Ensure NotesController publishes to NATS

### High memory usage
- Monitor number of active connections
- Check for connection leaks (Registry cleanup)
- Consider connection limits per user

## Future Enhancements

- [ ] Notification stream (mentions, likes, boosts)
- [ ] Direct message stream
- [ ] Hashtag streams
- [ ] User-specific filters
- [ ] Rate limiting per connection
- [ ] Reconnection tokens for resuming streams
