# Real-Time Engine Implementation Tree

```
sukhi-fedi/
├── elixir/lib/sukhi_fedi/
│   ├── feeds.ex                          # ✨ NEW - Feed query engine
│   ├── streaming/
│   │   ├── registry.ex                   # ✨ NEW - SSE connection registry
│   │   └── nats_listener.ex              # ✨ NEW - NATS message router
│   ├── web/
│   │   ├── router.ex                     # 📝 MODIFIED - Added feed routes
│   │   ├── feeds_controller.ex           # ✨ NEW - HTTP feed endpoints
│   │   ├── streaming_controller.ex       # ✨ NEW - SSE endpoints
│   │   └── notes_controller.ex           # 📝 MODIFIED - NATS publish
│   ├── application.ex                    # 📝 MODIFIED - Start streaming
│   └── auth.ex                           # 📝 MODIFIED - verify_token helper
├── STREAMING.md                          # ✨ NEW - Documentation
├── PRIORITY_2_SUMMARY.md                 # ✨ NEW - Implementation summary
├── streaming_demo.html                   # ✨ NEW - Browser demo
└── test_streaming.sh                     # ✨ NEW - Test script
```

## Component Relationships

```
Application Supervisor
├── Repo (PostgreSQL)
├── Bandit (HTTP Server)
│   └── Router
│       ├── FeedsController (HTTP feeds)
│       └── StreamingController (SSE)
├── Gnat (NATS Client)
├── Oban (Job Queue)
├── Cache.Ets
├── Streaming.Registry          # ✨ NEW
│   └── (manages SSE subscriptions)
└── Streaming.NatsListener      # ✨ NEW
    └── (routes NATS → Registry)
```

## Message Flow

```
NotesController
    │
    ├─→ PostgreSQL (save)
    │
    └─→ NATS.pub("stream.new_post")
            │
            ▼
        NatsListener
            │
            ├─→ Registry.broadcast(:local)
            │       │
            │       └─→ StreamingController (SSE clients)
            │
            └─→ Registry.broadcast(:home, account_id)
                    │
                    └─→ StreamingController (SSE clients)
```

## Key Design Decisions

1. **Registry Pattern**: GenServer-based registry for O(1) lookups
2. **Process Monitoring**: Automatic cleanup of dead connections
3. **NATS Topics**: Single topic `stream.new_post` for simplicity
4. **SSE Format**: Standard `event: update` with JSON payload
5. **Heartbeats**: 15-second interval to keep connections alive
6. **Authentication**: Bearer token in Authorization header
7. **Pagination**: Standard `limit` and `max_id` parameters

## Scalability Points

- **Horizontal**: Add more Elixir nodes (Registry syncs via Mnesia)
- **Vertical**: Increase connection limits per node
- **NATS**: Cluster NATS for high availability
- **Database**: Read replicas for feed queries
- **Caching**: ETS cache for follower lists (future)

## Testing Checklist

- [x] Feed queries return correct data
- [x] SSE connections establish successfully
- [x] NATS messages route correctly
- [x] Registry broadcasts to subscribers
- [x] Heartbeats keep connections alive
- [x] Disconnections clean up properly
- [x] Authentication works for home feed
- [x] Local feed is publicly accessible
- [ ] Load test with 1000+ connections
- [ ] Test with clustered Elixir nodes
- [ ] Test with NATS cluster
