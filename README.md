# Minimal Fediverse Implementation Spec
### Elixir + Deno (Fedify) — Native Scalability

---

## Philosophy

> **Elixir is the courier. Deno is the craftsman.**

- Elixir knows nothing about ActivityPub internals
- Deno knows nothing about HTTP routing or delivery
- NATS is the single boundary between them
- PostgreSQL is the single source of persistent truth

---

## Responsibility Split

| Concern | Elixir | Deno (Fedify) |
|---|---|---|
| HTTP receive / send | ✅ | ❌ |
| Authentication | ❌ (proxies token) | ✅ |
| Actor resolution | ❌ | ✅ |
| AP object generation | ❌ | ✅ |
| sign / verify | ❌ | ✅ |
| JSON-LD processing | ❌ | ✅ |
| WebFinger response | ❌ | ✅ |
| NodeInfo response | ❌ | ✅ |
| AP business logic | ❌ | ✅ |
| Follower list (DB) | ✅ | ❌ |
| Fan-out / delivery | ✅ | ❌ |
| Queue / retry | ✅ (Oban) | ❌ |
| Persistent storage | ✅ (PostgreSQL) | ❌ |
| Hot cache | ✅ (ETS) | ❌ |
| Key cache | ✅ (ETS) | ❌ |

---

## Architecture Overview

```
Internet
  │
  ▼ HTTPS
┌─────────────────────────────────┐
│  Elixir (Bandit + Plug)         │
│                                 │
│  ┌──────────┐  ┌─────────────┐  │
│  │   ETS    │  │    Oban     │  │
│  │ KeyCache │  │  (fan-out)  │  │
│  │ Sessions │  │  (delivery) │  │
│  └──────────┘  └─────────────┘  │
│         │             │         │
│         └──────┬──────┘         │
│                │                │
│         PostgreSQL              │
└────────────────┼────────────────┘
                 │ NATS
     ┌───────────┼───────────┐
     ▼           ▼           ▼
┌─────────┐ ┌─────────┐ ┌─────────┐
│  Deno   │ │  Deno   │ │  Deno   │
│ worker1 │ │ worker2 │ │ worker3 │
│ Fedify  │ │ Fedify  │ │ Fedify  │
└─────────┘ └─────────┘ └─────────┘
     │
     ▼
  Internet (outbound AP delivery from Deno is NOT done here)
```

> Deno workers are added/removed freely.
> NATS queue subscription distributes automatically.

---

## NATS Topic Design

All communication is **request/reply** via NATS.

```
ap.auth          token → actor (auth + resolve)
ap.verify        raw JSON-LD → ok | ng
ap.build.note    params → signed Note JSON-LD
ap.build.follow  params → signed Follow JSON-LD
ap.build.accept  params → signed Accept JSON-LD
ap.build.undo    params → signed Undo JSON-LD
ap.inbox         raw Activity JSON-LD → instruction
ap.webfinger     acct → WebFinger JSON
ap.nodeinfo      → NodeInfo JSON
```

### Message envelope (all topics)

```typescript
// Request
{
  request_id: string,   // for tracing
  payload: unknown
}

// Reply
{
  ok: boolean,
  data?: unknown,
  error?: string
}
```

---

## Data Flows

### 1. Outbound Post (user creates a Note)

```
POST /api/notes  { content, token }
  │
  ▼ Elixir
  NATS: ap.auth { token }
  │
  ▼ Deno
  verify token → resolve actor → return actor
  │
  ▼ Elixir
  NATS: ap.build.note { actor, content }
  │
  ▼ Deno
  build Note → sign → return signed JSON-LD + recipient inboxes
  │
  ▼ Elixir
  PostgreSQL: INSERT objects (raw_json)
  Oban: enqueue fan-out jobs (inbox_url × N)
  │
  ▼ Oban workers (parallel)
  HTTP POST → each inbox
```

### 2. Inbound Activity (receive from remote server)

```
POST /users/:name/inbox  { signed Activity }
  │
  ▼ Elixir
  NATS: ap.verify { raw JSON-LD }
  │
  ▼ Deno
  verify signature → return ok | ng
  │
  ▼ Elixir (if ok)
  NATS: ap.inbox { raw JSON-LD }
  │
  ▼ Deno
  AP business logic → return instruction:
    { action: "save", object: ... }
    { action: "save_and_reply", object: ..., reply: ... }
    { action: "ignore" }
  │
  ▼ Elixir
  execute instruction:
    save → PostgreSQL INSERT
    reply → Oban enqueue HTTP POST
    ignore → done
```

### 3. Inbound Follow

```
POST /inbox  { Follow activity }
  │
  ▼  (same verify flow as above)
  │
  ▼ Deno (ap.inbox)
  return {
    action: "save_and_reply",
    save: { follow relationship },
    reply: { signed Accept JSON-LD },
    inbox: requester_inbox_url
  }
  │
  ▼ Elixir
  PostgreSQL: INSERT follows (follower, followee, accepted)
  ETS: update follower cache
  Oban: deliver Accept to requester inbox
```

### 4. Outbound Post with Fan-out — Mastodon-compatible

```
POST /api/notes  { content, token }          (or note_cw / note_hashtag / note_emoji / note_media / mastodon_quote)
  │
  ▼ Elixir (ApiController)
  NATS: ap.auth { token }
  │
  ▼ Deno
  verify token → resolve actor → return actor JSON
  │
  ▼ Elixir
  NATS: ap.build.note  (or ap.build.note_cw / ap.build.note_hashtag / …)
        { actor, content, [summary, sensitive, hashtags, emoji, media, quoteUrl, …] }
  │
  ▼ Deno (registerMastodonHandlers → mastodon/*)
  build Note/Create → sign with actor private key
  → return { signed JSON-LD, recipientInboxes: [...] }
  │
  ▼ Elixir
  PostgreSQL: INSERT objects (ap_id, type="Note", raw_json)
  FanOut.enqueue(object, recipientInboxes)
  │
  ▼ Oban workers (one job per inbox, parallel, up to 10 retries)
  HTTP POST signed JSON-LD → each Mastodon inbox
  │
  ▼ Mastodon server
  receives Create{Note} activity
```

### 5. Outbound Post with Fan-out — Misskey-compatible

```
POST /api/notes  { content, token }          (or quote / poll / react / renote / talk)
  │
  ▼ Elixir (ApiController)
  NATS: ap.auth { token }
  │
  ▼ Deno
  verify token → resolve actor → return actor JSON
  │
  ▼ Elixir
  NATS: ap.build.note  (or ap.build.quote / ap.build.poll / ap.build.react /
                         ap.build.renote / ap.build.talk / ap.build.misskey_actor / …)
        { actor, content, [choices, multiple, endTime, quoteUrl, emoji, …] }
  │
  ▼ Deno (registerMisskeyHandlers → misskey/*)
  build Note/Create/Question/EmojiReact/Announce → sign with actor private key
  MFM → HTML conversion applied where needed (ap.mfm.to_html)
  → return { signed JSON-LD, recipientInboxes: [...] }
  │
  ▼ Elixir
  PostgreSQL: INSERT objects (ap_id, type="Note"/"Question"/"EmojiReact"/…, raw_json)
  FanOut.enqueue(object, recipientInboxes)
  │
  ▼ Oban workers (one job per inbox, parallel, up to 10 retries)
  HTTP POST signed JSON-LD → each Misskey inbox
  │
  ▼ Misskey server
  receives the activity
```

### 6. Inbound Post — Mastodon server sends to sukhi

```
POST /users/:name/inbox  { signed Create{Note} from Mastodon }
  │
  ▼ Elixir (InboxController)
  NATS: ap.verify { raw JSON-LD }
  │
  ▼ Deno (handlers/verify.ts)
  fetch actor public key → verify HTTP Signature → return ok | ng
  │
  ▼ Elixir (if ok)
  NATS: ap.inbox { raw JSON-LD }
  │
  ▼ Deno (handlers/inbox.ts)
  type == "Create" →
    Create.fromJsonLd → toJsonLd
    return { action: "save", object: normalized JSON-LD }
  │
  ▼ Elixir (Instructions.execute)
  PostgreSQL: INSERT objects (ap_id, type, actor_id, raw_json)
  respond 202 Accepted
```

### 7. Inbound Post — Misskey server sends to sukhi

```
POST /users/:name/inbox  (or /inbox)  { signed Create{Note} from Misskey }
  │
  ▼ Elixir (InboxController)
  NATS: ap.verify { raw JSON-LD }
  │
  ▼ Deno (handlers/verify.ts)
  fetch actor public key → verify HTTP Signature → return ok | ng
  │
  ▼ Elixir (if ok)
  NATS: ap.inbox { raw JSON-LD }
  │
  ▼ Deno (handlers/inbox.ts)
  type == "Create" →
    Create.fromJsonLd → toJsonLd
    return { action: "save", object: normalized JSON-LD }
    (Misskey-specific extensions such as MFM are preserved in raw_json as-is)
  │
  ▼ Elixir (Instructions.execute)
  PostgreSQL: INSERT objects (ap_id, type, actor_id, raw_json)
  respond 202 Accepted
```

### 8. WebFinger / NodeInfo

```
GET /.well-known/webfinger?resource=acct:user@domain
  │
  ▼ Elixir
  ETS lookup (cache hit?) → return immediately
  ETS miss →
    NATS: ap.webfinger { acct }
    │
    ▼ Deno
    build WebFinger JSON
    │
    ▼ Elixir
    ETS: cache (TTL 10min)
    return response
```

---

## PostgreSQL Schema (minimal)

```sql
-- Accounts (local users)
CREATE TABLE accounts (
  id          BIGSERIAL PRIMARY KEY,
  username    TEXT NOT NULL UNIQUE,
  display_name TEXT,
  summary     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- AP Objects (immutable after insert)
CREATE TABLE objects (
  id          BIGSERIAL PRIMARY KEY,
  ap_id       TEXT NOT NULL UNIQUE,   -- full URL id
  type        TEXT NOT NULL,          -- Note, Follow, etc.
  actor_id    TEXT NOT NULL,
  raw_json    JSONB NOT NULL,         -- signed JSON-LD as-is
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON objects (actor_id);
CREATE INDEX ON objects (created_at DESC);

-- Follow relationships
CREATE TABLE follows (
  id           BIGSERIAL PRIMARY KEY,
  follower_uri TEXT NOT NULL,
  followee_id  BIGINT NOT NULL REFERENCES accounts(id),
  state        TEXT NOT NULL DEFAULT 'pending', -- pending | accepted
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (follower_uri, followee_id)
);

-- Delivery log (managed by Oban)
CREATE TABLE deliveries (
  id          BIGSERIAL PRIMARY KEY,
  object_id   BIGINT NOT NULL REFERENCES objects(id),
  inbox_url   TEXT NOT NULL,
  state       TEXT NOT NULL DEFAULT 'queued',
  attempts    INT NOT NULL DEFAULT 0,
  next_retry  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

> `raw_json` stores the complete signed JSON-LD.
> Deno creates it, Elixir stores it, nobody modifies it.

---

## ETS Cache Design (Elixir)

```elixir
# Tables
:key_cache      # {key_id, public_key, expiry}   TTL: 1 hour
:webfinger      # {acct, json, expiry}            TTL: 10 min
:follower_list  # {account_id, [follower_uris]}   TTL: 5 min
:session        # {token_hash, actor_uri, expiry} TTL: from Deno

# All tables: read_concurrency: true
# TTL sweep: GenServer every 60s
```

---

## Elixir Project Structure

```
elixir/
├── lib/
│   ├── web/
│   │   ├── router.ex           # Plug router
│   │   ├── inbox_controller.ex
│   │   ├── webfinger_controller.ex
│   │   └── api_controller.ex
│   ├── ap/
│   │   ├── client.ex           # NATS request/reply wrapper
│   │   └── instructions.ex     # parse Deno instructions
│   ├── delivery/
│   │   ├── fan_out.ex          # resolve inboxes, enqueue
│   │   └── worker.ex           # Oban HTTP POST job
│   ├── cache/
│   │   ├── ets.ex              # ETS wrapper + TTL sweep
│   │   └── key_cache.ex
│   └── repo/
│       └── migrations/
└── mix.exs
```

---

## Deno Project Structure

```
deno/
├── main.ts                   # NATS subscriber entrypoint
├── handlers/
│   ├── auth.ts               # token verify + actor resolve
│   ├── verify.ts             # AP signature verification
│   ├── inbox.ts              # AP business logic
│   ├── build/
│   │   ├── note.ts
│   │   ├── follow.ts
│   │   └── accept.ts
│   └── wellknown/
│       ├── webfinger.ts
│       └── nodeinfo.ts
├── fedify/
│   └── context.ts            # fedify setup, key loading
└── deno.json
```

---

## API Endpoints

All endpoints accept and return `application/json`. Authentication for user-facing API is done via a `token` field in the request body.

### GET /.well-known/webfinger

WebFinger endpoint for actor discovery.

| Query Param | Type | Required | Description |
|---|---|---|---|
| `resource` | string | ✅ | Resource identifier (e.g., `acct:alice@example.com`) |

```bash
curl -X GET "http://localhost:4000/.well-known/webfinger?resource=acct:alice@example.com"
```

### POST /inbox (Shared) or /users/:name/inbox

ActivityPub inbox for receiving activities from other actors.

```bash
curl -X POST http://localhost:4000/inbox \
  -H "Content-Type: application/activity+json" \
  -d '{
    "@context": "https://www.w3.org/ns/activitystreams",
    "id": "https://example.com/activities/1",
    "type": "Follow",
    "actor": "https://example.com/users/bob",
    "object": "https://your.domain/users/alice"
  }'
```

### POST /api/accounts

Create a new account. Generates an Ed25519 key pair via the Deno worker and stores the account in the database.

| Field | Type | Required | Description |
|---|---|---|---|
| `username` | string | ✅ | Unique username for the account |
| `display_name` | string | ❌ | Display name shown on the profile |
| `summary` | string | ❌ | Profile bio / description |

**Response (201):**

| Field | Type | Description |
|---|---|---|
| `id` | integer | Internal account ID |
| `username` | string | The created username |
| `actor_uri` | string | Full ActivityPub actor URI |

```bash
curl -X POST http://localhost:4000/api/accounts \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","display_name":"Alice","summary":"Hello!"}'
```

---

### POST /api/tokens

Issue an authentication token for an existing account. The token is stored on the account and used to authenticate subsequent API requests.

| Field | Type | Required | Description |
|---|---|---|---|
| `username` | string | ✅ | Username of the account to issue a token for |

**Response (201):**

| Field | Type | Description |
|---|---|---|
| `token` | string | Bearer token to use in subsequent API calls |

```bash
curl -X POST http://localhost:4000/api/tokens \
  -H "Content-Type: application/json" \
  -d '{"username":"alice"}'
```

---

### POST /api/notes

Create a plain note.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `content` | string | ✅ | Note text (MFM supported) |

```bash
curl -X POST http://localhost:4000/api/notes \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_TOKEN","content":"Hello, Fediverse!"}'
```

### POST /api/notes/cw

Create a note with a content warning.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `content` | string | ✅ | Note text |
| `summary` | string | ✅ | CW summary (shown before expanding) |
| `sensitive` | boolean | ❌ | Mark as sensitive (default: `true`) |

```bash
curl -X POST http://localhost:4000/api/notes/cw \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_TOKEN","content":"spoiler body","summary":"CW: spoiler"}'
```

### POST /api/boosts

Boost (Announce) an existing AP object.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `object` | string | ✅ | URL of the AP object to boost |

```bash
curl -X POST http://localhost:4000/api/boosts \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_TOKEN","object":"https://example.com/users/alice/notes/123"}'
```

### POST /api/reacts

React to an AP object with an emoji.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `object` | string | ✅ | URL of the AP object to react to |
| `emoji` | string | ✅ | Emoji character or shortcode |

```bash
curl -X POST http://localhost:4000/api/reacts \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_TOKEN","object":"https://example.com/users/alice/notes/123","emoji":"👍"}'
```

### POST /api/quotes

Create a note that quotes another AP object.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `content` | string | ✅ | Note text |
| `quote_url` | string | ✅ | URL of the AP object to quote |

```bash
curl -X POST http://localhost:4000/api/quotes \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_TOKEN","content":"Interesting!","quote_url":"https://example.com/users/alice/notes/123"}'
```

### POST /api/polls

Create a poll.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `content` | string | ✅ | Poll question text |
| `choices` | string[] | ✅ | Array of choice strings |
| `multiple` | boolean | ❌ | Allow multiple votes (default: `false`) |
| `end_time` | string | ❌ | ISO 8601 expiry datetime |

```bash
curl -X POST http://localhost:4000/api/polls \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_TOKEN","content":"Favorite language?","choices":["Elixir","TypeScript","Other"]}'
```

### Response

All endpoints return `201 Created` on success:

```json
{ "id": "https://your.domain/notes/<uuid>" }
```

On error, `400 Bad Request` is returned:

```json
{ "error": "<reason>" }
```

---

## Scaling Strategy

### When AP processing is the bottleneck

```bash
# Just add more Deno workers
# NATS queue subscription distributes automatically
docker run deno-worker &
docker run deno-worker &
docker run deno-worker &
```

No config change needed anywhere.

### When delivery is the bottleneck

```bash
# Add Elixir nodes
# Oban distributes across nodes automatically
```

### When DB is the bottleneck

```
Add PostgreSQL read replica
→ Elixir reads follower lists from replica
→ writes still go to primary
```

### Scale thresholds (single Deno process)

| Load | Status |
|---|---|
| ~10 req/s | 😄 single Deno, no concern |
| ~1,000 req/s | 🟡 add KeyCache warmup |
| ~5,000 req/s | 🟡 add Deno worker × 2 |
| ~10,000 req/s | 🔴 add Deno worker × N |

---

## What is NOT needed

| Component | Reason |
|---|---|
| Redis | ETS covers all hot cache needs |
| Separate sign/verify service | sign is tightly coupled to AP object building |
| Auth middleware in Elixir | token proxied to Deno, Elixir stays AP-ignorant |
| Message schema registry | simple JSON envelope is enough at this scale |

---

## Phase Plan

### Phase 1 — Make it work
```
Elixir (single node)
  + Deno × 1
  + NATS (single broker)
  + PostgreSQL (single instance)
```

### Phase 2 — Make it scale (when needed)
```
Deno × N (add workers freely)
ETS TTL tuning
Oban concurrency tuning
```

### Phase 3 — Make it resilient (when needed)
```
Elixir cluster (Mnesia for ETS sync)
PostgreSQL read replica
NATS cluster (JetStream for at-least-once delivery)
```

---

## Key Design Principles

1. **Elixir never parses AP semantics** — it only routes, stores, and delivers
2. **Deno never touches HTTP** — it only builds, signs, verifies, and reasons about AP
3. **NATS is the only boundary** — no shared memory, no direct DB access from Deno
4. **signed JSON-LD is immutable** — created by Deno, stored by Elixir, never modified
5. **Scale by adding workers** — no redesign needed to go from 10/s to 10,000/s
