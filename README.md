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

### 4. WebFinger / NodeInfo

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
