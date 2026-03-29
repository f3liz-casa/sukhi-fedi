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
| Integrity proofs (FEP-8b32) | ❌ | ✅ |
| HTTP signature (RFC 9421 / cavage) | ❌ | ✅ |
| JSON-LD processing | ❌ | ✅ |
| WebFinger response | ❌ | ✅ |
| NodeInfo response | ❌ | ✅ |
| AP business logic | ❌ | ✅ |
| Follower list (DB) | ✅ | ❌ |
| Fan-out / delivery | ✅ | ❌ |
| Queue / retry | ✅ (Oban) | ❌ |
| Followers sync (FEP-8fcf) | ✅ (Oban) | ❌ |
| Persistent storage | ✅ (PostgreSQL) | ❌ |
| Hot cache | ✅ (ETS) | ❌ |
| Key cache | ✅ (ETS) | ❌ |
| Relay management | ✅ | ❌ |
| Prometheus metrics | ✅ (PromEx) | ❌ |
| OpenTelemetry tracing | ✅ | ✅ |

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
│  └──────────┘  │  (fol-sync) │  │
│         │      └─────────────┘  │
│         └──────┬────────────────┘
│                │
│         PostgreSQL
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
ap.auth                    token → actor (auth + resolve)
ap.verify                  raw JSON-LD → ok | ng
ap.build.note              params → signed Note JSON-LD
ap.build.follow            params → signed Follow JSON-LD
ap.build.accept            params → signed Accept JSON-LD
ap.build.undo              params → signed Undo JSON-LD
ap.build.dm                params → signed DM Create(Note) JSON-LD
ap.build.add               params → signed Add JSON-LD (pin)
ap.build.remove            params → signed Remove JSON-LD (unpin)
ap.build.integrity_proof   object → object + DataIntegrityProof
ap.sign.delivery           {url, headers, body, keyId} → signed headers
ap.inbox                   raw Activity JSON-LD → instruction
ap.webfinger               acct → WebFinger JSON
ap.nodeinfo                → NodeInfo JSON
db.dm.create               params → saved DM + thread
db.dm.list                 {actor} → conversation list
db.dm.conversation.get     {conversationId} → messages
db.note.pin                {noteId, accountId} → ok
db.note.unpin              {noteId, accountId} → ok
db.admin.relay.subscribe   {actorUri, inboxUri} → relay
db.admin.relay.unsubscribe {id} → ok
db.admin.relay.list        → relays[]
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

### 9. Direct Message (DM)

```
POST /v1/conversations  { token, recipientUri, content, [conversationId, inReplyToId] }
  │
  ▼ Elixir
  NATS: ap.auth { token }
  │
  ▼ Deno → actor JSON
  │
  ▼ Elixir
  NATS: ap.build.dm { actor, recipientUri, content, … }
  │
  ▼ Deno (handlers/build/dm.ts)
  build Note (to: [recipient], cc: []) → sign
  inject _misskey_content for Misskey compatibility
  → return { signed JSON-LD, recipientInboxes: [recipient_inbox] }
  │
  ▼ Elixir
  NATS: db.dm.create { … }
  │
  ▼ Deno (api/conversations.ts)
  PostgreSQL: INSERT notes (conversation_ap_id, in_reply_to_ap_id)
              INSERT conversation_participants
  │
  ▼ Elixir
  Oban: deliver DM to recipient inbox
```

### 10. Pin / Unpin Note (Featured Collection)

```
POST /v1/notes/:id/pin  { token }
  │
  ▼ Elixir
  NATS: ap.auth { token }
  │
  ▼ Deno → actor JSON
  │
  ▼ Elixir
  NATS: ap.build.add { actor, object: noteApId, target: featuredCollectionUri }
  │
  ▼ Deno (handlers/build/collection_op.ts)
  build Add activity → sign
  → return { signed JSON-LD, recipientInboxes: [...] }
  │
  ▼ Elixir
  NATS: db.note.pin { noteId, accountId }
  │
  ▼ Deno (api/notes.ts)
  PostgreSQL: INSERT pinned_notes (account_id, note_id, position)
  │
  ▼ Elixir
  Oban: fanout Add activity to followers
```

### 11. Followers Collection Sync (FEP-8fcf)

```
Inbound inbox request with Collection-Synchronization header
  │
  ▼ Elixir (InboxController)
  parse Collection-Synchronization: url=...; digest=<sha256>
  │
  ▼ compare digest against local followers
  match → skip sync
  mismatch →
    Oban: enqueue FollowerSyncWorker
    │
    ▼ FollowerSyncWorker (Oban, queue: federation)
    fetch remote actor's followers collection
    │
    ▼ FollowersSync.reconcile/2
    diff remote collection vs local follows
    mark stale follows as removed
```

### 12. Relay Management

```
POST /api/admin/relays  { actor_uri, inbox_uri }  (admin token required)
  │
  ▼ Elixir
  Relays.subscribe(actor_uri, inbox_uri)
  PostgreSQL: INSERT relays (actor_uri, inbox_uri, state="pending")
  │
  ▼ Oban: deliver Follow activity to relay inbox
  │
  ▼ Relay sends back Accept(Follow)
  ▼ Elixir (InboxController)
  Relays.mark_accepted(relay_id)
  PostgreSQL: UPDATE relays SET state="accepted"
```

> Active relays are included in fan-out recipient lists automatically.

---

## PostgreSQL Schema

```sql
-- Accounts (local users)
CREATE TABLE accounts (
  id          BIGSERIAL PRIMARY KEY,
  username    TEXT NOT NULL UNIQUE,
  display_name TEXT,
  summary     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- AP Objects / Notes (immutable after insert)
CREATE TABLE objects (
  id                  BIGSERIAL PRIMARY KEY,
  ap_id               TEXT NOT NULL UNIQUE,   -- full URL id
  type                TEXT NOT NULL,          -- Note, Follow, etc.
  actor_id            TEXT NOT NULL,
  raw_json            JSONB NOT NULL,         -- signed JSON-LD as-is
  in_reply_to_ap_id   TEXT,                   -- parent message (DMs / threads)
  conversation_ap_id  TEXT,                   -- conversation context URI
  quote_of_ap_id      TEXT,                   -- quoted note AP ID
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON objects (actor_id);
CREATE INDEX ON objects (created_at DESC);
CREATE INDEX ON objects (in_reply_to_ap_id);
CREATE INDEX ON objects (conversation_ap_id);
CREATE INDEX ON objects (quote_of_ap_id);

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

-- DM conversation participants
CREATE TABLE conversation_participants (
  id                  BIGSERIAL PRIMARY KEY,
  conversation_ap_id  TEXT NOT NULL,
  account_id          BIGINT NOT NULL REFERENCES accounts(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (conversation_ap_id, account_id)
);

-- Pinned / featured notes
CREATE TABLE pinned_notes (
  id          BIGSERIAL PRIMARY KEY,
  account_id  BIGINT NOT NULL REFERENCES accounts(id),
  note_id     BIGINT NOT NULL REFERENCES objects(id),
  position    INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (account_id, note_id)
);
CREATE INDEX ON pinned_notes (account_id, position);

-- ActivityPub relay subscriptions
CREATE TABLE relays (
  id            BIGSERIAL PRIMARY KEY,
  actor_uri     TEXT NOT NULL UNIQUE,
  inbox_uri     TEXT NOT NULL,
  state         TEXT NOT NULL DEFAULT 'pending', -- pending | accepted | rejected
  created_by_id BIGINT REFERENCES accounts(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON relays (state);
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

## Observability

### OpenTelemetry (Deno)

```typescript
// otel.ts — tracer name: "sukhi-fedi-deno" v0.1.0
// Requires: deno run --unstable-otel
// Configure via standard OTEL_* env vars:
//   OTEL_EXPORTER_OTLP_ENDPOINT=http://collector:4318
//   OTEL_SERVICE_NAME=sukhi-fedi-deno
```

### Prometheus Metrics (Elixir)

```
GET /metrics
```

Exposes BEAM VM, Ecto, Oban queue, and application metrics via PromEx.

---

## Elixir Project Structure

```
elixir/
├── lib/
│   ├── web/
│   │   ├── router.ex                  # Plug router
│   │   ├── inbox_controller.ex
│   │   ├── api_controller.ex
│   │   ├── actor_controller.ex
│   │   ├── collection_controller.ex   # followers / following collections
│   │   ├── featured_controller.ex     # pinned notes collection
│   │   └── db_nats_listener.ex
│   ├── ap/
│   │   ├── client.ex                  # NATS request/reply wrapper
│   │   └── instructions.ex            # parse Deno instructions
│   ├── delivery/
│   │   ├── fan_out.ex                 # resolve inboxes, enqueue
│   │   ├── worker.ex                  # Oban HTTP POST job
│   │   ├── followers_sync.ex          # FEP-8fcf reconcile
│   │   └── follower_sync_worker.ex    # Oban follower sync job
│   ├── schema/
│   │   ├── note.ex
│   │   ├── conversation_participant.ex
│   │   ├── pinned_note.ex
│   │   └── relay.ex
│   ├── pinned_notes.ex                # pin / unpin / list featured
│   ├── relays.ex                      # relay CRUD + state machine
│   ├── prom_ex.ex                     # Prometheus metrics
│   ├── release.ex                     # mix release tasks
│   └── repo/
│       └── migrations/
└── mix.exs
```

---

## Deno Project Structure

```
deno/
├── main.ts                        # NATS subscriber entrypoint
├── otel.ts                        # OpenTelemetry tracer setup
├── api.ts                         # Hono app + route mounts
├── api/
│   ├── notes.ts                   # notes + pin/unpin routes
│   ├── conversations.ts           # DM thread routes
│   └── admin.ts                   # relay admin routes
├── handlers/
│   ├── auth.ts                    # token verify + actor resolve
│   ├── verify.ts                  # AP signature verification
│   ├── inbox.ts                   # AP business logic
│   ├── sign_delivery.ts           # HTTP signature (RFC 9421 / cavage)
│   └── build/
│       ├── note.ts
│       ├── follow.ts
│       ├── accept.ts
│       ├── announce.ts
│       ├── dm.ts                  # Direct Message builder
│       ├── collection_op.ts       # Add / Remove (pin / unpin)
│       └── integrity_proof.ts     # FEP-8b32 DataIntegrityProof
├── fedify/
│   ├── context.ts                 # fedify setup, key loading
│   └── utils.ts
└── deno.json
```

---

## API Endpoints

All endpoints accept and return `application/json`. Authentication for user-facing API is done via a `token` field in the request body (or `Authorization: Bearer` header on `/v1/*` routes).

### GET /.well-known/webfinger

WebFinger endpoint for actor discovery.

| Query Param | Type | Required | Description |
|---|---|---|---|
| `resource` | string | ✅ | Resource identifier (e.g., `acct:alice@example.com`) |

```bash
curl "http://localhost:4000/.well-known/webfinger?resource=acct:alice@example.com"
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

### GET /users/:name/followers

Returns the actor's followers as an ActivityPub `OrderedCollection`.

### GET /users/:name/following

Returns the actor's following list as an ActivityPub `OrderedCollection`.

### GET /users/:name/featured

Returns the actor's pinned notes as an ActivityPub `OrderedCollection`.

---

### POST /api/accounts

Create a new account. Generates an Ed25519 key pair via the Deno worker.

| Field | Type | Required | Description |
|---|---|---|---|
| `username` | string | ✅ | Unique username |
| `display_name` | string | ❌ | Display name |
| `summary` | string | ❌ | Profile bio |

```bash
curl -X POST http://localhost:4000/api/accounts \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","display_name":"Alice","summary":"Hello!"}'
```

**Response (201):** `{ "id": 1, "username": "alice", "actor_uri": "https://your.domain/users/alice" }`

---

### POST /api/tokens

Issue an authentication token for an account.

| Field | Type | Required | Description |
|---|---|---|---|
| `username` | string | ✅ | Username |

```bash
curl -X POST http://localhost:4000/api/tokens \
  -H "Content-Type: application/json" \
  -d '{"username":"alice"}'
```

**Response (201):** `{ "token": "..." }`

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

Note with a content warning.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `content` | string | ✅ | Note text |
| `summary` | string | ✅ | CW label |
| `sensitive` | boolean | ❌ | Default: `true` |

### POST /api/boosts

Boost (Announce) an existing AP object.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `object` | string | ✅ | AP object URL to boost |

### POST /api/reacts

React to an AP object with an emoji.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `object` | string | ✅ | AP object URL |
| `emoji` | string | ✅ | Emoji character or shortcode |

### POST /api/quotes

Quote-post another AP object.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `content` | string | ✅ | Note text |
| `quote_url` | string | ✅ | URL of object to quote |

### POST /api/polls

Create a poll.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `content` | string | ✅ | Poll question |
| `choices` | string[] | ✅ | Choice labels |
| `multiple` | boolean | ❌ | Allow multiple votes (default: `false`) |
| `end_time` | string | ❌ | ISO 8601 expiry |

---

### POST /v1/notes/:id/pin

Pin a note to the actor's featured collection. Fans out a signed `Add` activity to followers.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |

**Response (200):** `{ "id": "..." }`

### DELETE /v1/notes/:id/pin

Unpin a note. Fans out a signed `Remove` activity.

**Response (204)**

---

### POST /v1/conversations

Create a new DM thread or reply to an existing one.

| Field | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |
| `recipient_uri` | string | ✅ | AP actor URI of recipient |
| `content` | string | ✅ | Message body |
| `conversation_id` | string | ❌ | Existing conversation AP ID (for replies) |
| `in_reply_to_id` | string | ❌ | AP ID of message being replied to |

**Response (201):** `{ "id": "https://your.domain/notes/<uuid>" }`

### GET /v1/conversations

List conversation threads for the authenticated user.

| Query Param | Type | Required | Description |
|---|---|---|---|
| `token` | string | ✅ | Auth token |

### GET /v1/conversations/:id

Get all messages in a conversation thread.

---

### POST /api/admin/relays

Subscribe to an ActivityPub relay. Sends a `Follow` activity to the relay inbox.

| Field | Type | Required | Description |
|---|---|---|---|
| `actor_uri` | string | ✅ | Relay actor URI |
| `inbox_uri` | string | ✅ | Relay inbox URL |

**Response (201):** `{ "id": 1, "actor_uri": "...", "state": "pending" }`

### DELETE /api/admin/relays/:id

Unsubscribe from a relay. Sends `Undo(Follow)` to the relay.

**Response (204)**

### GET /api/admin/relays

List all relay subscriptions.

---

### Common Response Codes

| Status | Meaning |
|---|---|
| 201 | Created successfully |
| 202 | Accepted (async, e.g. inbox) |
| 204 | No content (delete) |
| 400 | Bad request: `{ "error": "<reason>" }` |
| 401 | Unauthorized |

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
| ~10 req/s | single Deno, no concern |
| ~1,000 req/s | add KeyCache warmup |
| ~5,000 req/s | add Deno worker × 2 |
| ~10,000 req/s | add Deno worker × N |

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
6. **Standards first** — RFC 9421, FEP-8b32 (integrity proofs), FEP-8fcf (followers sync)
