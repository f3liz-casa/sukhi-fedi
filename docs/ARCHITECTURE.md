# sukhi-fedi Architecture

> **This document is the canonical architecture reference.** A fresh
> contributor can rebuild the system from scratch using only this file
> plus the code. The only companion doc is
> [`ADDONS.md`](ADDONS.md), which specifies the addon ABI.

## 1. Product intent

`sukhi-fedi` is a **federated (ActivityPub) SNS server** with Mastodon-
and Misskey-compatible APIs. Users sign in locally, publish Notes,
follow remote actors, and receive posts from any compatible fediverse
server.

Design north star: **one Elixir gateway + one Elixir delivery node +
one stateless Bun worker fleet + one distributed-Erlang plugin node**,
coordinated by **PostgreSQL (system of record) + NATS (event plane)**.
Nothing else is a hard dependency.

## 2. Boundary lines

```
 users (HTTPS)                                    remote servers (HTTPS)
      │                                                   ▲
      ▼                                                   │
 ╔══════════════════════════════════╗     ╔══════════════════════════════════╗
 ║      elixir — 案内人 (gateway)    ║     ║      delivery — 配達員            ║
 ║  Bandit/Plug  / WS streaming     ║     ║  Outbox.Relay                     ║
 ║  OAuth / WebAuthn / session      ║     ║  (LISTEN/NOTIFY → JetStream)      ║
 ║  inbox POST receive + dispatch   ║     ║  Oban :delivery / :federation     ║
 ║  Outbox *write side* (Ecto.Multi)║     ║  HTTP POST + retries              ║
 ║  WebFinger / NodeInfo            ║     ║  Collection-Synchronization       ║
 ║  Routes /api/v1 + /api/admin →api║     ║  signs via fedify.sign.v1         ║
 ╚═════════════════════════════╤════╝     ╚═════════════════════════════╤════╝
                               │                                        │
                               ▼                                        │
                PostgreSQL (system of record, Ecto) ◄───reads outbox────┘
                + outbox (gateway writes, delivery reads)
                + delivery_receipts (delivery writes, idempotency)
                + oban_jobs (shared table, disjoint queues)
                               │
                               ▼
                NATS JetStream
                ├─ stream OUTBOX        (sns.outbox.>)    — delivery publishes
                └─ stream DOMAIN_EVENTS (sns.events.>)    — streaming
                               │
                ┌──────────────┼────────────────┐
                ▼                               ▼
 ╔══════════════════════════════════╗  ╔═════════════════════════════╗
 ║      Bun — 翻訳家 + 印鑑職人      ║  ║  api — REST plugin node     ║
 ║  NATS Micro service "fedify"     ║  ║  (:sukhi_api, BEAM node)    ║
 ║    fedify.translate.v1           ║  ║  :rpc-invoked from gateway  ║
 ║    fedify.sign.v1                ║  ║  Mastodon / Misskey APIs    ║
 ║    fedify.verify.v1              ║  ║  capabilities auto-register ║
 ║    fedify.ping.v1                ║  ║                             ║
 ║  queue group "fedify-workers"    ║  ║                             ║
 ║  NO HTTP server — NATS-only      ║  ║                             ║
 ╚══════════════════════════════════╝  ╚═════════════════════════════╝
```

Rules enforced by this split:

1. **Only the gateway speaks HTTP to users.** Bun has no HTTP server; the
   delivery node speaks HTTP only outbound to remote inboxes.
2. **Only the gateway writes to the core schema** (notes, follows,
   outbox row inserts, …). The delivery node reads `outbox`, `accounts`,
   `follows`, `objects`, `relays` and writes `delivery_receipts` — a
   narrow, stable projection.
3. **All outbound ActivityPub deliveries live on the delivery node**,
   never Bun and never the gateway. Gateway inserts Oban jobs by
   fully-qualified worker string (`SukhiDelivery.Delivery.Worker`) into
   the shared `oban_jobs` table; only delivery polls the `:delivery`
   queue, so only delivery executes them.
4. **Gateway ↔ Delivery is Postgres + NATS.** No distributed Erlang on
   that edge. Distributed Erlang is reserved for the `api/` plugin node,
   which needs synchronous request/reply for Mastodon REST.
5. **Bun owns JSON-LD + HTTP Signature only.** Fedify's opinionated
   ActivityPub handling is exactly this slice, so we lean on it there.
6. **Mastodon/Misskey REST runs on the api plugin node**, reached via
   distributed Erlang `:rpc` — no HTTP hop, no JSON-over-NATS envelope.

## 3. Repository layout

```
sukhi-fedi/
├── elixir/                                # 案内人 (gateway only)
│   ├── lib/sukhi_fedi/
│   │   ├── application.ex                 # supervision tree
│   │   ├── addon.ex / addon/registry.ex   # addon ABI + discovery
│   │   ├── repo.ex
│   │   ├── outbox.ex                      # Outbox.enqueue / enqueue_multi
│   │   │                                    (write side only; delivery
│   │   │                                    node owns the Relay / read side)
│   │   ├── federation/
│   │   │   ├── actor_fetcher.ex           # remote actor GET + ETS cache
│   │   │   └── fedify_client.ex           # NATS Micro client → Bun (admin)
│   │   ├── schema/                        # Ecto schemas (note, account,
│   │   │   │                                follow, boost, reaction, …)
│   │   │   └── outbox_event.ex            # `outbox` table
│   │   ├── cache/ets.ex                   # ETS TTL cache
│   │   ├── ap/                            # ActivityPub helpers
│   │   │   ├── client.ex                  # legacy NATS req/reply (ap.*)
│   │   │   └── instructions.ex            # inbox activity dispatcher
│   │   ├── nats/                          # db.* topic handlers
│   │   │   ├── helpers.ex
│   │   │   ├── accounts.ex                # db.account.* / db.auth.* / db.social.*
│   │   │   ├── notes.ex                   # db.note.* / db.bookmark.* / db.dm.*
│   │   │   ├── content.ex                 # db.article.* / db.media.* / db.emoji.* / db.feed.*
│   │   │   └── admin.ex                   # db.moderation.* / db.admin.*
│   │   ├── addons/                        # first-party addons
│   │   │   ├── nodeinfo_monitor.ex + nodeinfo_monitor/
│   │   │   ├── streaming.ex + streaming/
│   │   │   ├── articles.ex / bookmarks.ex / feeds.ex / media.ex / mfm.ex
│   │   │   ├── moderation.ex / pinned_notes.ex / web_push.ex
│   │   └── web/                           # controllers + plugs
│   │       ├── router.ex
│   │       ├── rate_limit_plug.ex
│   │       ├── plugin_plug.ex             # :rpc to api plugin node
│   │       ├── inbox_controller.ex
│   │       ├── webfinger_controller.ex
│   │       ├── nodeinfo_controller.ex
│   │       ├── collection_controller.ex   # followers / following collections
│   │       └── …
│   ├── priv/repo/migrations/
│   │   ├── core/                          # core schema (notes, follows, outbox, …)
│   │   └── addons/<id>/                   # per-addon migrations
│   ├── test/
│   │   ├── support/integration_case.ex
│   │   ├── integration/                   # E2E (docker-compose.test.yml)
│   │   ├── web/                           # unit tests
│   │   └── test_helper.exs                # excludes :integration
│   ├── config/{config,dev,prod,runtime,test}.exs
│   ├── mix.exs / mix.lock
│   └── Dockerfile
│
├── delivery/                              # 配達員 (separate BEAM node)
│   ├── lib/sukhi_delivery/
│   │   ├── application.ex                 # supervision tree
│   │   ├── repo.ex
│   │   ├── outbox/relay.ex                # LISTEN/NOTIFY → JetStream
│   │   ├── delivery/
│   │   │   ├── worker.ex                  # Oban :delivery queue
│   │   │   ├── fan_out.ex                 # latent (future outbox consumer)
│   │   │   ├── fedify_client.ex           # NATS Micro client → Bun
│   │   │   ├── followers_sync.ex          # FEP-8fcf
│   │   │   └── follower_sync_worker.ex    # Oban :federation queue
│   │   ├── schema/                        # read-only projection of the
│   │   │                                    gateway's core schema
│   │   │   ├── outbox_event.ex / delivery_receipt.ex
│   │   │   └── account.ex / follow.ex / object.ex / relay.ex
│   │   ├── relays.ex                      # get_active_inbox_urls/0
│   │   ├── prom_ex.ex                     # metrics on :4001
│   │   └── release.ex                     # stub (gateway owns migrations)
│   ├── config/{config,dev,prod,runtime,test}.exs
│   ├── test/delivery/worker_test.exs
│   ├── mix.exs
│   └── Dockerfile
│
├── bun/                                   # 翻訳家 + 印鑑職人
│   ├── services/fedify_service.ts         # ★ NATS Micro service
│   ├── main.ts                            # legacy ap.verify + ap.inbox
│   ├── handlers/
│   │   ├── build/{note,follow,accept,announce,actor,dm,collection_op,
│   │   │           like,undo,delete}.ts   # one translator per type
│   │   ├── verify.ts                      # HTTP Signature verify
│   │   ├── sign_delivery.ts               # HTTP Signature sign
│   │   ├── inbox.ts                       # legacy ap.inbox dispatcher
│   │   └── inbox_test.ts
│   ├── fedify/
│   │   ├── context.ts                     # cachedDocumentLoader
│   │   ├── keys.ts                        # local-actor key store (actor creation)
│   │   ├── key_cache.ts                   # imported CryptoKey cache (sign path)
│   │   └── utils.ts                       # signAndSerialize, injectDefined, …
│   ├── addons/
│   │   ├── loader.ts                      # ABI check + enabled/disabled filter
│   │   ├── types.ts                       # BunAddon + TranslateHandler
│   │   ├── mastodon_api/manifest.ts
│   │   └── misskey_api/manifest.ts
│   ├── package.json                       # TS 6.0.3, @fedify/fedify 1.x,
│   │                                        @js-temporal/polyfill, @nats-io/*
│   ├── tsconfig.json
│   └── Dockerfile                         # oven/bun:1-alpine
│
├── api/                                   # ★ Mastodon/Misskey REST plugin node
│   ├── mix.exs                            # independent :sukhi_api app
│   ├── lib/sukhi_api/
│   │   ├── application.ex                 # start-up; prints registered routes
│   │   ├── capability.ex                  # @behaviour + `use` macro (auto-register)
│   │   ├── registry.ex                    # runtime discovery of capability modules
│   │   ├── router.ex                      # :rpc entry — handle(req) → {:ok, resp}
│   │   ├── gateway_rpc.ex                 # calls back to gateway contexts
│   │   └── capabilities/                  # ← DROP FILES HERE TO ADD ENDPOINTS
│   │       ├── mastodon_instance.ex
│   │       └── nodeinfo_monitor.ex
│   ├── config/{config,dev,prod,runtime,test}.exs
│   └── Dockerfile                         # distributed Erlang release
│
├── infra/
│   ├── nats/bootstrap.sh                  # JetStream stream bootstrap
│   └── terraform/ · ansible/              # infra-as-code (OCI)
│
├── docker-compose.yml                     # dev + prod stack (pinned GHCR images)
├── docker-compose.test.yml                # hermetic test stack
└── docs/
    ├── ARCHITECTURE.md                    # ← this file
    └── ADDONS.md                          # addon ABI contract
```

## 4. NATS topology

### 4.1 JetStream streams

Defined declaratively in `infra/nats/bootstrap.sh` (run by the
`nats-bootstrap` sidecar in compose).

| Stream          | Subjects         | Storage | Retention  | Notes                                              |
| --------------- | ---------------- | ------- | ---------- | -------------------------------------------------- |
| `OUTBOX`        | `sns.outbox.>`   | file    | WorkQueue  | Exactly-once relay; consumed by fan-out / timeline |
| `DOMAIN_EVENTS` | `sns.events.>`   | file    | Limits 7d  | Broadcast events for WebSocket / notifications     |

`dupe-window = 2m` on both, which combined with `Nats-Msg-Id = outbox-<id>`
on publish gives stream-level dedup.

### 4.2 Subject taxonomy

```
sns.<context>.<aggregate>.<op>[.<variant>]
```

| Subject                            | Direction | Emitted by                    | Consumed by                  |
| ---------------------------------- | --------- | ----------------------------- | ---------------------------- |
| `sns.outbox.note.created`          | pub       | `Notes.create_note/1`         | deliverer / timeline-updater |
| `sns.outbox.note.deleted`          | pub       | `Notes.delete_note/1`         | deliverer                    |
| `sns.outbox.follow.requested`      | pub       | `Social.follow/2`             | deliverer                    |
| `sns.outbox.like.created`          | pub       | `Notes.create_like/2`         | deliverer                    |
| `sns.outbox.like.undone`           | pub       | `Notes.delete_like/2`         | deliverer                    |
| `sns.outbox.announce.created`      | pub       | `Notes.create_boost/2`        | deliverer                    |
| `sns.events.timeline.home.updated` | pub       | timeline-updater (addon)      | streaming-fanout             |
| `sns.events.notification.mention`  | pub       | inbox handler                 | streaming-fanout             |

### 4.3 NATS Micro services (Bun-side)

Service name: `fedify`, version `0.2.0`, queue group `fedify-workers`.
Multiple Bun replicas auto-share load.

| Endpoint              | Request                                                       | Response                                 |
| --------------------- | ------------------------------------------------------------- | ---------------------------------------- |
| `fedify.ping.v1`      | raw bytes                                                     | echoes request (health check)            |
| `fedify.translate.v1` | `{object_type, payload}`                                      | `{ok:true, data:{…}}`                    |
| `fedify.sign.v1`      | `{actorUri, inbox, body, privateKeyJwk, keyId, algorithm?}`   | `{ok:true, data:{headers:{…}}}`          |
| `fedify.verify.v1`    | `{method, url, headers, body}`                                | `{ok:true, data:{ok:bool, …}}`           |

Core `object_type` values accepted by translate (in
`bun/services/fedify_service.ts`): `note`, `follow`, `accept`,
`announce`, `actor`, `dm`, `add`, `remove`, `like`, `undo`, `delete`.
Addons contribute additional keys under an `<addon_id>.<type>`
namespace; core keys cannot be overridden (`addons/loader.ts` enforces
this at startup).

Service discovery: NATS Micro auto-publishes `$SRV.{PING,INFO,STATS}.fedify`.

### 4.4 Legacy NATS surface

Two legacy surfaces still live during the ongoing strangler-fig
migration:

- **`ap.verify` / `ap.inbox`** on `bun/main.ts` — subscribe-loop handlers
  for incoming signature verification and inbox activity dispatch. The
  inbox controller still calls these via `SukhiFedi.AP.Client.request/2`.
  Everything else graduated to `fedify.*`.
- **`db.>`** wildcard on `SukhiFedi.Web.DbNatsListener` — request/reply
  for Postgres reads/writes from the Bun HTTP API that used to live in
  `bun/` before stage 3-b. The HTTP layer is gone; the `db.*` topics
  remain only because the api plugin node and a handful of addons still
  use them as a convenient RPC shim. Handlers live in
  `SukhiFedi.Nats.{Accounts, Notes, Content, Admin}`.

## 5. Transactional Outbox

The foundational correctness pattern. Without it, `DB insert + NATS pub`
is two independent writes and a crash between them loses or duplicates
events.

### 5.1 Schema

Migration `core/20260420000001_create_outbox.exs`:

```
outbox(
  id bigserial PRIMARY KEY,
  aggregate_type text NOT NULL,    -- "note", "follow", …
  aggregate_id   text NOT NULL,
  subject        text NOT NULL,    -- e.g. "sns.outbox.note.created"
  payload        jsonb NOT NULL,
  headers        jsonb NOT NULL DEFAULT '{}',
  status         text NOT NULL DEFAULT 'pending',   -- pending | published | failed
  attempts       integer NOT NULL DEFAULT 0,
  last_error     text,
  inserted_at    timestamptz NOT NULL DEFAULT now(),
  published_at   timestamptz
)
-- partial index — keeps hot set tiny once published rows dominate
create index(:outbox, [:id], where: "status = 'pending'")
create index(:outbox, [:aggregate_type, :aggregate_id])

-- Statement-level trigger (not per-row): one NOTIFY per INSERT
-- statement, regardless of how many rows got inserted in bulk.
AFTER INSERT ON outbox FOR EACH STATEMENT EXECUTE FUNCTION outbox_notify();
```

Core migration `core/20260420000005_add_hot_path_indexes.exs` performs
the partial-index swap and the `FOR EACH STATEMENT` trigger upgrade.
Same migration adds `notes(visibility, created_at)` for the public
timeline and `follows(followee_id, state)` + `follows(follower_uri,
state)` for the FEP-8fcf and "who follows X" paths.

Plus `delivery_receipts` (migration `core/20260420000002`):

```
delivery_receipts(
  id bigserial PRIMARY KEY,
  activity_id  text NOT NULL,   -- ActivityPub Activity id
  inbox_url    text NOT NULL,
  status       text NOT NULL,   -- delivered | failed | gone
  delivered_at timestamptz,
  inserted_at  timestamptz NOT NULL
)
unique_index(delivery_receipts, [activity_id, inbox_url])
```

### 5.2 Write path (producer)

All domain writes that need federation use
`SukhiFedi.Outbox.enqueue_multi/6` inside a single `Ecto.Multi` with
the domain insert:

```elixir
Ecto.Multi.new()
|> Ecto.Multi.insert(:note, Note.changeset(%Note{}, attrs))
|> Outbox.enqueue_multi(:outbox_event,
     "sns.outbox.note.created", "note",
     & &1.note.id,
     fn %{note: note} -> %{note_id: note.id, …} end)
|> Repo.transaction()
```

DB commit ⇒ outbox row is durable. Period.

Implemented call sites:
- `SukhiFedi.Notes.create_note/1`  → `sns.outbox.note.created`
- `SukhiFedi.Notes.delete_note/1`  → `sns.outbox.note.deleted`
- `SukhiFedi.Notes.create_like/2`  → `sns.outbox.like.created`
- `SukhiFedi.Notes.delete_like/2`  → `sns.outbox.like.undone`
- `SukhiFedi.Notes.create_boost/2` → `sns.outbox.announce.created`
- `SukhiFedi.Social.follow/2`      → `sns.outbox.follow.requested`

### 5.3 Relay path (consumer of outbox, producer to NATS)

`SukhiFedi.Outbox.Relay` is a singleton GenServer in the supervision tree:

1. On boot: `Postgrex.Notifications.listen/2` on `outbox_new`, then
   force an immediate tick to catch rows left from a prior run.
2. Wakeup triggers: NOTIFY from trigger, or a 30 s fallback timer.
3. Each tick:
   ```
   SELECT FROM outbox WHERE status='pending' AND attempts<10
   ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED
   ```
   — the `SKIP LOCKED` lets multiple relay instances cooperate safely
   for future horizontal scale.
4. For each claimed row: `Gnat.pub/4` to JetStream with
   `Nats-Msg-Id: outbox-<id>` header (stream dedup).
5. Outcomes are bucketed, then two statements finish the tick:
   - one `update_all` flips all successful ids to `status='published',
     published_at=now()`;
   - failures keep per-row updates (each row's `last_error` differs,
     and the cold path is bounded by `max_attempts=10`). Failed rows
     flip to `status='failed'` once attempts reach the cap.

## 6. End-to-end flows

### 6.1 Local user posts a Note

```
POST /api/v1/statuses
   │  (matched by /api/v1/*_ in router.ex → PluginPlug → :rpc api node)
   │   The capability there calls SukhiFedi.Notes.create_note/1 via
   │   gateway_rpc.
   ▼
Elixir Notes.create_note/1
   Ecto.Multi:
     insert notes
     insert outbox(sns.outbox.note.created)
   commit  ──▶ AFTER INSERT STATEMENT TRIGGER fires NOTIFY outbox_new
                         │
                         ▼
              Outbox.Relay (wakes up)
                         │  Gnat.pub to JetStream OUTBOX
                         ▼
         (consumer — future work: ap-deliverer reads OUTBOX and calls
          Delivery.FanOut.enqueue/2)
                         │  fan out to each follower inbox
                         ▼
         Delivery.FanOut.enqueue(object, inbox_urls)
           1. read Object's raw_json once
           2. compute FEP-8fcf header_value(actor_uri) once
           3. build a list of job args with
              {raw_json, actor_uri, activity_id, sync_header, inbox_url}
           4. Oban.insert_all — one INSERT per fan-out, not one per inbox
                         │
                         ▼ (one Oban job per follower inbox)
         Delivery.Worker (Oban queue :delivery, max_attempts 10)
          1. check delivery_receipts(activity_id, inbox_url) — skip if delivered
          2. resolve body from args["raw_json"] (no DB round-trip)
          3. attach Collection-Synchronization header from args["sync_header"]
          4. sign envelope: FedifyClient.sign(...) → NATS Micro to Bun,
             which fetches a cached CryptoKey from bun/fedify/key_cache.ts
          5. Req.post inbox_url  via named Finch pool (size 50 × 4)
          6. on 2xx → insert delivery_receipt
          7. on non-2xx / error → Oban exp backoff, max 10 attempts
```

All the work that is invariant across a fan-out (body encode, follower
digest, signing key import) happens exactly once per activity rather
than once per recipient. See `SukhiFedi.Delivery.FanOut` for the
precomputation, `bun/fedify/key_cache.ts` for the Bun CryptoKey reuse.

### 6.2 Remote server delivers to our inbox

```
POST /users/alice/inbox  (external Mastodon)
   │
   ▼
Elixir InboxController (captures raw body + headers)
   │
   ▼
AP.Client.request("ap.verify", {payload})
   │   legacy NATS req/reply → Bun main.ts handleVerify
   │   {ok: true} or {ok: false}
   ▼
AP.Client.request("ap.inbox", {payload})
   │   legacy NATS req/reply → Bun main.ts handleInbox
   │   returns an Instructions map
   ▼
Instructions.execute(instruction)
   │   Follow / Accept / Create(Note) / Announce / Like / Delete / Undo
   │   + FEP-8fcf: if request carried a Collection-Synchronization
   │     header, enqueue FollowerSyncWorker to reconcile local follows
   ▼
DB writes + (sometimes) an Oban job (e.g. an Accept back)
   │
   ▼
202 Accepted
```

`Instructions.execute/1` also catches incoming `Delete` to scrub local
object mirrors and `Undo(Follow)` to remove follow rows. DMs are
materialised into local notes with `visibility = "direct"` and
conversation participants are recorded.

### 6.3 WebFinger (local actor lookup)

```
GET /.well-known/webfinger?resource=acct:alice@example.tld
   ▼
WebfingerController (Elixir, no Bun call)
   1. parse acct → username, domain
   2. if domain == our domain:
        Accounts.get_account_by_username/1
        build JRD (subject, links: self → actor URL)
        cache in ETS :webfinger table (10 min TTL)
   3. else: 404 (we don't proxy foreign webfingers)
```

### 6.4 NodeInfo

```
GET /.well-known/nodeinfo            → discovery JSON (links to /nodeinfo/2.1)
GET /nodeinfo/2.1                    → static info (version, software, usage)
   ▼
NodeinfoController (Elixir, pure)
```

### 6.5 Followers / following collections

`GET /users/:name/followers` and `GET /users/:name/following` are
served by `SukhiFedi.Web.CollectionController` with a single JOIN query
(`Social.list_followers/2` / `Social.list_following/2`) — no per-item
round-trip to hydrate account data.

## 7. Addon system

Three layers can each host addon-contributed code; they declare
themselves with matching ids and share the same `ENABLED_ADDONS` /
`DISABLE_ADDONS` env vars.

### Gateway (`elixir/lib/sukhi_fedi/`)

```elixir
defmodule SukhiFedi.Addons.Streaming do
  use SukhiFedi.Addon, id: :streaming
  @impl true
  def supervision_children,
    do: [SukhiFedi.Addons.Streaming.Registry, SukhiFedi.Addons.Streaming.NatsListener]
end
```

`SukhiFedi.Addon.Registry` scans compiled modules for the persistent
`@sukhi_fedi_addon` attribute at boot, verifies each addon's
`abi_version` major against core (`"1"`), applies the enable/disable
filter, and returns supervision children + NATS subscriptions. Major-
version mismatch is a boot-time crash. Migrations under
`priv/repo/migrations/addons/<id>/` run per-addon at release time.

### Bun (`bun/addons/`)

```ts
const myAddon: BunAddon = {
  id: "my_addon",
  abi_version: "1.0",
  translators: { "my_addon.widget": handleBuildWidget },
};
export default myAddon;
```

Register in `bun/addons/loader.ts` (static list — Bun imports are
compile-time). Addons contribute extra `fedify.translate.v1` keys and
legacy `ap.*` subscribes. Core translators cannot be overridden.

### API plugin node (`api/lib/sukhi_api/capabilities/`)

Each file one capability; `use SukhiApi.Capability, addon: :mastodon_api`
tags it. Untagged capabilities are treated as core. `SukhiApi.Registry`
discovers them at boot via `:application.get_key(:sukhi_api, :modules)`
and filters by the same env vars. DB access goes back through the
gateway (`gateway_rpc`) so the plugin node doesn't run its own Ecto
pool.

See `docs/ADDONS.md` for the full ABI.

## 8. API plugin node (distributed Erlang)

The Mastodon / Misskey REST surface runs as a **separate BEAM node**
under `api/`. The gateway reaches it with `:rpc.call/5` via
`SukhiFedi.Web.PluginPlug`; no HTTP hop, no JSON-over-NATS envelope,
just Erlang distribution over the docker-compose network.

```
client  ──HTTPS──▶  Elixir gateway (node gateway@elixir)
                    └─ router match "/api/v1/*_" or "/api/admin/*_"
                       └─ SukhiFedi.Web.PluginPlug
                          └─ :rpc.call(api@api, SukhiApi.Router, :handle, [req])
                                           │
                                           ▼
                                   api BEAM node (node api@api)
                                   SukhiApi.Registry (auto-discovery)
                                     └─ Capabilities.MastodonInstance
                                     └─ Capabilities.<more>       ← one file = one feature
```

**Request / response contract** (see `SukhiApi.Capability` moduledoc):

```
req  :: %{method: "GET" | "POST" | …, path: "/api/v1/…",
          query: "a=1&b=2", headers: [{k, v}], body: binary}
resp :: %{status: 200, body: iodata, headers: [{k, v}]}
```

**Adding an endpoint** — drop a file in `api/lib/sukhi_api/capabilities/`:

```elixir
defmodule SukhiApi.Capabilities.InstancePeers do
  use SukhiApi.Capability, addon: :mastodon_api  # or omit for core

  @impl true
  def routes, do: [{:get, "/api/v1/instance/peers", &peers/1}]

  def peers(_req), do: {:ok, %{status: 200, body: "[]",
                               headers: [{"content-type", "application/json"}]}}
end
```

That's the entire change. No router edit, no manifest update — the
`use SukhiApi.Capability` macro persists a module attribute;
`SukhiApi.Registry` scans `:application.get_key(:sukhi_api, :modules)`
at runtime and picks up every such module.

**Failure modes**:

- no `plugin_nodes` configured → 503 `{"error":"plugin_unavailable"}`
- node unreachable at `:rpc` time → 503 `{"error":"plugin_rpc_failed"}`
- handler crashes on the remote node → remote catches and returns 500
- path not covered by any capability → remote returns 404

## 9. Observability (OpenTelemetry-free)

- **Metrics**: `PromEx` exposes `/metrics` on port 4000. External
  scraper (self-hosted Prometheus, Grafana Cloud Free, …) pulls from
  there. Out of the box: Ecto / Oban / Plug / BEAM system metrics;
  custom metrics via `:telemetry.execute` + `telemetry_metrics`.
- **Dashboards**: not provided in-repo. Point a Grafana instance at
  the Prometheus scraper consuming `http://<host>:4000/metrics`.
- **Traces**: deliberately **not** instrumented. We rejected
  OpenTelemetry / Jaeger / otelcol because (a) Fedify's OTel
  integration is heavy, (b) the operational tax doesn't pay off at our
  scale, and (c) structured logs with a `request_id` cover the
  replay-the-path use case. `elixir/mix.exs` has zero `opentelemetry_*`
  deps on purpose.
- **Structured logging**: every controller / worker should log with
  `Logger.metadata(request_id: …)` so a single incident can be
  reconstructed via `grep`.

Custom metrics to emit as we build each feature:
| Metric                            | Type      | Where                |
| --------------------------------- | --------- | -------------------- |
| `sukhi_outbox_pending_count`      | gauge     | `Outbox.Relay` tick  |
| `sukhi_outbox_publish_rate`       | counter   | `Outbox.Relay`       |
| `sukhi_delivery_success_rate`     | counter   | `Delivery.Worker`    |
| `sukhi_delivery_failure_rate`     | counter   | `Delivery.Worker`    |
| `sukhi_fedify_latency_ms`         | histogram | `FedifyClient`       |
| `sukhi_inbox_request_rate`        | counter   | `InboxController`    |
| `sukhi_delivery_pool_utilization` | gauge     | Finch telemetry       |

## 10. Environment variables

| Var                              | Service | Default                 | Purpose                            |
| -------------------------------- | ------- | ----------------------- | ---------------------------------- |
| `DB_HOST` / `USER` / `PASS` / `NAME` | Elixir | (required in prod) | Postgres connection                |
| `DB_POOL_SIZE`                   | Elixir  | `10`                    | Ecto pool size                     |
| `NATS_HOST` / `NATS_PORT`        | Elixir  | `127.0.0.1:4222`        | NATS client                        |
| `NATS_URL`                       | Bun     | `nats://localhost:4222` | NATS client                        |
| `PLUGIN_NODES`                   | Elixir  | `api@api` (compose)     | Space/comma node list for `:rpc`   |
| `RELEASE_COOKIE`                 | Elixir+api | `sukhi_fedi_dev_cookie` | distributed Erlang shared secret |
| `DOMAIN` / `INSTANCE_TITLE`      | api     | `localhost:4000` / `sukhi-fedi` | NodeInfo / WebFinger output |
| `ENABLED_ADDONS` / `DISABLE_ADDONS` | all  | `all` / `""`            | Comma-separated addon ids          |

## 11. Running locally

### Dev stack
```bash
docker-compose up -d        # postgres + nats + nats-bootstrap + gateway + bun + api + watchtower
# http://localhost:4000             — Elixir gateway
# http://localhost:4000/metrics     — PromEx (scrape externally)
```

### Test stack (hermetic, distinct ports)
```bash
docker-compose -f docker-compose.test.yml up -d
# Postgres : localhost:15432   (db: sukhi_fedi_test, ephemeral tmpfs)
# NATS     : localhost:14222   (monitor: :18222)
# fedify-service : NATS Micro service queue "fedify-workers"
```

### Running tests

```bash
# Elixir unit tests (hermetic, no live deps):
cd elixir && mix test --no-start

# Elixir integration tests (needs docker-compose.test.yml up):
cd elixir && mix test --only integration

# Bun tests:
cd bun && bun test

# Type-check the whole bun surface (TS 6.0.3 via tsc):
cd bun && bun run check
```

## 12. Horizontal scale posture

- Elixir and Bun are designed to be **stateless** — all state lives in
  Postgres or NATS. `mix release` + `docker compose up --scale
  gateway=N` adds gateway replicas; identical Bun containers
  auto-load-balance via the NATS Micro queue group `fedify-workers`.
- `Outbox.Relay`'s `FOR UPDATE SKIP LOCKED` makes running multiple
  relay instances safe — each claims a disjoint batch.
- ETS caches (WebFinger JRDs, remote actor fetches, imported CryptoKeys
  on Bun) are **node-local**; misses fall back to Postgres or a remote
  HTTP fetch, so cache inconsistency across nodes is harmless.
- Future `SUKHI_ROLE=inbox|api|worker|all` env switch lets a single
  image start with different supervision subtrees, so a node can
  specialize in e.g. inbox intake under DoS without affecting user API.

## 13. Migration philosophy (strangler-fig)

The repo arrived at its current shape via small, always-mergeable
stages; each kept `mix test` + `bun test` green and could ship
independently.

```
0   scaffolding            ✅ done
1   Outbox infra           ✅ done
2   NATS Micro (additive)  ✅ done
2-b remove old ap.*        ✅ FedifyClient-scope done; legacy ap.verify/inbox still live
3   HTTP consolidation     ✅ WebFinger / NodeInfo / ActorFetcher / RateLimitPlug
3-b Bun HTTP removal       ✅ bun/lib/ deleted (no Hono server); bun/api/ handlers removed
3-c Plugin API (api/)      ✅ distributed-Erlang plugin node; capabilities auto-register
4   Delivery to Elixir     ✅ Worker uses FedifyClient + delivery_receipts
4-b Finch pool + E2E       ✅ Finch pool 50×4 per host
5   God-module split       ✅ db_nats_listener 617 → 80 line dispatcher + 5 Nats.* modules
6   docs + dead-code purge ✅ stale docs removed; README/ARCHITECTURE align
7   Hot-path optimisation  ✅ FanOut precomputes (body, digest), Oban.insert_all,
                              Outbox.Relay bulk update_all, partial outbox index,
                              per-statement NOTIFY, notes/follows indexes,
                              Bun CryptoKey cache
```

If you're adding a feature, first decide which stage it belongs in and
whether it should be deferred until the stage completes.
