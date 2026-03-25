# Sukhi Fedi - Complete Architecture (Priorities 2-5)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           INTERNET / FEDIVERSE                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         ELIXIR HTTP LAYER                               │
├─────────────────────────────────────────────────────────────────────────┤
│  ActivityPub Endpoints:                                                 │
│    • GET  /.well-known/webfinger    (Actor discovery)                  │
│    • GET  /users/:name              (Actor profile)                     │
│    • GET  /users/:name/outbox       (Public activities)                │
│    • POST /users/:name/inbox        (Receive activities)               │
│    • POST /inbox                    (Shared inbox)                      │
│                                                                          │
│  API Endpoints (Priority 2-5):                                          │
│    • GET  /api/feeds/{home,local}   (HTTP feeds)                       │
│    • GET  /api/streaming/*          (SSE streaming)                    │
│    • POST /api/notes                (Create post)                       │
│    • POST /api/likes                (Like)                              │
│    • POST /api/boosts               (Boost/Announce)                   │
│    • POST /api/reactions            (Emoji reactions - P4)             │
│    • POST /api/polls/vote           (Poll voting - P4)                 │
│    • POST /api/mute                 (Mute user - P5)                   │
│    • POST /api/block                (Block user - P5)                  │
│    • POST /api/reports              (Report abuse - P5)                │
│    • POST /api/bookmarks            (Bookmark note - P5)               │
│    • POST /api/articles             (Create article - P5)              │
│    • POST /api/media/upload-url     (S3 presigned URL - P4)           │
│    • GET  /api/emojis               (Custom emojis - P4)               │
│                                                                          │
│  Admin Endpoints (Priority 5):                                          │
│    • GET  /api/admin/reports                                           │
│    • POST /api/admin/instance-blocks                                   │
│    • POST /api/admin/accounts/:id/suspend                              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            NATS MESSAGE BUS                             │
├─────────────────────────────────────────────────────────────────────────┤
│  Subjects:                                                              │
│    • ap.verify          → Signature verification                       │
│    • ap.inbox           → Activity processing                          │
│    • ap.like.build      → Build Like activity                          │
│    • ap.announce.build  → Build Announce activity                      │
│    • ap.undo.build      → Build Undo activity                          │
│    • ap.reaction.build  → Build EmojiReact (P4)                        │
│    • ap.article.build   → Build Article (P5)                           │
│    • streaming.home     → Home feed events (P2)                        │
│    • streaming.local    → Local feed events (P2)                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        DENO ACTIVITYPUB LAYER                           │
├─────────────────────────────────────────────────────────────────────────┤
│  Handlers (using Fedify):                                               │
│    • verify.ts          → HTTP Signature verification                  │
│    • inbox.ts           → Process 15+ activity types                   │
│    • like.ts            → Build Like activities                        │
│    • undo.ts            → Build Undo activities                        │
│    • reaction.ts        → Build EmojiReact (P4)                        │
│    • moderation.ts      → Handle Block/Flag (P5)                       │
│    • article.ts         → Handle Article (P5)                          │
│                                                                          │
│  Supported Activities:                                                  │
│    Follow, Accept, Create, Update, Delete, Like, Announce, Undo,       │
│    EmojiReact, Move, Block, Flag, Add, Remove, Question, Article       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         ELIXIR BUSINESS LOGIC                           │
├─────────────────────────────────────────────────────────────────────────┤
│  Context Modules:                                                       │
│    • Accounts          → User management                                │
│    • Notes             → Post management                                │
│    • Social            → Follow/unfollow                                │
│    • Feeds             → Timeline queries (with filtering - P5)         │
│    • Streaming         → SSE connections (P2)                           │
│    • Media             → S3 uploads, blurhash (P4)                      │
│    • Moderation        → Mute, block, reports (P5)                     │
│    • Bookmarks         → Private collections (P5)                       │
│    • Articles          → Long-form content (P5)                         │
│    • WebPush           → Push notifications (P5)                        │
│                                                                          │
│  Background Jobs (Oban):                                                │
│    • DeliveryWorker    → Federate activities to remote inboxes         │
│    • RetryWorker       → Exponential backoff on failures                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          POSTGRESQL DATABASE                            │
├─────────────────────────────────────────────────────────────────────────┤
│  Core Tables:                                                           │
│    • accounts          → Users (with is_admin, suspended_at - P5)      │
│    • notes             → Posts (with cw, mfm - P4)                     │
│    • objects           → ActivityPub objects                            │
│    • follows           → Follow relationships                           │
│    • deliveries        → Outbound federation queue                      │
│                                                                          │
│  Priority 4 Tables (Misskey):                                           │
│    • media             → Media library (S3, blurhash, tags)            │
│    • emojis            → Custom emoji library                           │
│    • reactions         → Emoji reactions on notes                       │
│    • polls             → Poll definitions                               │
│    • poll_options      → Poll choices                                   │
│    • poll_votes        → User votes                                     │
│                                                                          │
│  Priority 5 Tables (Moderation):                                        │
│    • mutes             → User mutes (with expiration)                  │
│    • blocks            → User blocks                                    │
│    • reports           → Abuse reports                                  │
│    • instance_blocks   → Defederated domains                           │
│    • bookmarks         → Private saved notes                            │
│    • push_subscriptions → Web Push endpoints                           │
│    • articles          → Long-form content                              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          EXTERNAL SERVICES                              │
├─────────────────────────────────────────────────────────────────────────┤
│    • S3 / Cloudflare R2  → Media storage (presigned URLs - P4)        │
│    • Web Push Service    → Push notifications (P5)                     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Examples

### 1. Incoming Activity (Federation)
```
Remote Server → POST /inbox → Elixir HTTP
                            ↓
                    NATS (ap.verify)
                            ↓
                    Deno (verify signature)
                            ↓
                    NATS (ap.inbox)
                            ↓
                    Deno (parse activity)
                            ↓
                    Elixir (store in DB)
                            ↓
                    NATS (streaming.*)
                            ↓
                    SSE clients (real-time update)
```

### 2. Outgoing Activity (Federation)
```
User → POST /api/likes → Elixir HTTP
                       ↓
                NATS (ap.like.build)
                       ↓
                Deno (build activity)
                       ↓
                Elixir (store + queue)
                       ↓
                Oban DeliveryWorker
                       ↓
                Remote Server inbox
```

### 3. Real-time Streaming (Priority 2)
```
User → GET /api/streaming/home → Elixir SSE
                                ↓
                        NATS subscribe (streaming.home)
                                ↓
                        New activity arrives
                                ↓
                        NATS publish (streaming.home)
                                ↓
                        SSE push to client
```

### 4. Media Upload (Priority 4)
```
User → POST /api/media/upload-url → Elixir
                                   ↓
                            Generate S3 presigned URL
                                   ↓
                            Return URL to client
                                   ↓
User → PUT to S3 (direct upload)
                                   ↓
User → POST /api/media (confirm)
                                   ↓
                            Store metadata + blurhash
```

### 5. Moderation Flow (Priority 5)
```
User → POST /api/block → Elixir
                       ↓
                Store in blocks table
                       ↓
                NATS (ap.block.build)
                       ↓
                Deno (build Block activity)
                       ↓
                Federate to remote server
                       ↓
                Feed queries auto-filter blocked users
```

## Scaling Strategy

### Horizontal Scaling
- **Elixir**: Add more nodes (BEAM clustering)
- **Deno**: Add more workers (NATS load balancing)
- **PostgreSQL**: Read replicas for feeds
- **NATS**: Cluster mode for HA

### Performance Optimizations
- Indexed foreign keys (all tables)
- Efficient feed queries with filtering
- Background job processing (Oban)
- SSE connection pooling
- S3 direct uploads (no proxy)

### Capacity Estimates (Single Node)
- ~1,000 req/s inbox processing
- ~1,000 concurrent SSE connections
- ~10 delivery workers (configurable)
- Sub-100ms feed queries

## Security Layers

1. **HTTP Signature Verification** (Deno/Fedify)
2. **Authentication** (Bearer tokens)
3. **Authorization** (Admin checks - P5)
4. **Feed Filtering** (Block/mute/defederation - P5)
5. **Content Sanitization** (MFM - P4)
6. **Rate Limiting** (TODO)

## Complete Feature Matrix

| Feature | Priority | Status |
|---------|----------|--------|
| HTTP Feeds | 2 | ✅ |
| SSE Streaming | 2 | ✅ |
| ActivityPub Federation | 3 | ✅ |
| HTTP Signatures | 3 | ✅ |
| Follow/Accept | 3 | ✅ |
| Like/Announce | 3 | ✅ |
| Media Library | 4 | ✅ |
| Custom Emojis | 4 | ✅ |
| Emoji Reactions | 4 | ✅ |
| MFM Support | 4 | ✅ |
| Polls | 4 | ✅ |
| Mute/Block | 5 | ✅ |
| Reports | 5 | ✅ |
| Instance Blocks | 5 | ✅ |
| User Suspension | 5 | ✅ |
| Bookmarks | 5 | ✅ |
| Web Push API | 5 | ✅ |
| Articles | 5 | ✅ |

---

**Total Implementation:**
- 5 Priorities Complete
- 23 Database Tables
- 50+ API Endpoints
- 15+ ActivityPub Types
- 2 Languages (Elixir + Deno)
- 1 Message Bus (NATS)
- 100% Federated
