# sukhi-fedi Architecture

> **This document is the canonical architecture reference.** A fresh
> contributor can rebuild the system from scratch using only this file
> plus the code. The only companion doc is
> [`ADDONS.md`](ADDONS.md), which specifies the addon ABI.

## 1. Product intent

`sukhi-fedi` is a **federated (ActivityPub) SNS server** with Mastodon- and
Misskey-compatible APIs. Users sign in locally, publish Notes, follow
remote actors, and receive posts from any compatible fediverse server.

Design north star: **one Elixir gateway + one stateless Bun worker fleet**,
coordinated by **PostgreSQL (system of record) + NATS (event plane)**.
Nothing else is a hard dependency.

## 2. Boundary lines

```
 users (HTTPS)         remote servers (HTTPS)
      │                       │
      ▼                       ▼
 ╔══════════════════════════════════════════════╗
 ║           Elixir — 案内人 + 配達員            ║
 ║  Bandit/Plug  /  WebSocket streaming          ║
 ║  Mastodon/Misskey-compat API                  ║
 ║  OAuth / WebAuthn / session                   ║
 ║  inbox POST receive + dispatch                ║
 ║  Outbox.Relay  (LISTEN/NOTIFY → JetStream)    ║
 ║  Oban delivery workers (HTTP POST + retries)  ║
 ║  WebFinger / NodeInfo (direct, no proxy)      ║
 ╚═════════════════════════════════╤════════════╝
                                   │
      PostgreSQL (system of record, Ecto)
      + outbox table (exactly-once-effectively)
      + delivery_receipts (per-inbox idempotency)
                                   │
      NATS JetStream
      ├─ stream OUTBOX        (sns.outbox.>)
      └─ stream DOMAIN_EVENTS (sns.events.>)
                                   │
                                   ▼
 ╔══════════════════════════════════════════════╗
 ║        Bun — 翻訳家 + 印鑑職人                ║
 ║  NATS Micro service "fedify"                  ║
 ║    fedify.translate.v1  (JSON-LD build)       ║
 ║    fedify.sign.v1       (HTTP Signature)      ║
 ║    fedify.verify.v1     (signature verify)    ║
 ║    fedify.ping.v1       (health)              ║
 ║  queue group "fedify-workers" → auto LB       ║
 ║  NO HTTP server. NATS-only.                   ║
 ╚══════════════════════════════════════════════╝
```

Rules enforced by this split:

1. **Only Elixir speaks HTTP to the outside world** (both users and remote
   servers). No Bun HTTP server in the target state.
2. **Only Elixir writes to Postgres.** Bun is stateless.
3. **All outbound deliveries flow through Oban on Elixir**, never Bun.
   BEAM's lightweight processes handle fan-out to thousands of followers
   without breaking a sweat; Bun's single-thread event loop would choke.
4. **Bun owns JSON-LD + HTTP Signature only.** Fedify's
   opinionated ActivityPub handling is exactly this slice, so we lean on
   it where it wins.

## 3. Repository layout

```
sukhi-fedi/
├── elixir/                                # Case 案内人 + 配達員
│   ├── lib/sukhi_fedi/
│   │   ├── application.ex                 # supervision tree
│   │   ├── repo.ex                        # Ecto Repo
│   │   ├── outbox.ex                      # Outbox.enqueue / enqueue_multi
│   │   ├── outbox/relay.ex                # LISTEN/NOTIFY → JetStream
│   │   ├── delivery/
│   │   │   ├── fedify_client.ex           # NATS Micro client → Deno
│   │   │   ├── worker.ex                  # Oban delivery worker
│   │   │   ├── fan_out.ex                 # enqueues per-follower jobs
│   │   │   ├── followers_sync.ex          # FEP-8fcf support
│   │   │   └── follower_sync_worker.ex
│   │   ├── federation/actor_fetcher.ex    # remote actor GET + ETS cache
│   │   ├── schema/                        # Ecto schemas
│   │   │   ├── account.ex / note.ex / follow.ex / …
│   │   │   ├── outbox_event.ex            # `outbox` table
│   │   │   └── delivery_receipt.ex
│   │   ├── cache/ets.ex                   # ETS TTL cache
│   │   ├── ap/                            # ActivityPub helpers
│   │   │   ├── client.ex                  # legacy NATS req/reply (ap.*)
│   │   │   └── instructions.ex            # inbox activity dispatcher
│   │   ├── nats/                          # db.* topic handlers (split from god module)
│   │   │   ├── helpers.ex                 # shared envelope + serializers
│   │   │   ├── accounts.ex                # db.account.* / db.auth.* / db.social.*
│   │   │   ├── notes.ex                   # db.note.* / db.bookmark.* / db.dm.*
│   │   │   ├── content.ex                 # db.article.* / db.media.* / db.emoji.* / db.feed.*
│   │   │   └── admin.ex                   # db.moderation.* / db.admin.*
│   │   ├── streaming/                     # WebSocket streaming
│   │   └── web/                           # controllers + plugs
│   │       ├── router.ex
│   │       ├── rate_limit_plug.ex
│   │       ├── inbox_controller.ex
│   │       ├── webfinger_controller.ex
│   │       ├── nodeinfo_controller.ex
│   │       └── …
│   ├── priv/repo/migrations/
│   │   ├── 20240001000000_*                # initial schema
│   │   ├── 20260325000000_*_add_priority_* # features
│   │   ├── 20260420000001_create_outbox.exs
│   │   └── 20260420000002_create_delivery_receipts.exs
│   ├── test/
│   │   ├── support/integration_case.ex
│   │   ├── integration/                   # E2E (docker-compose.test.yml)
│   │   ├── web/ · delivery/               # unit tests
│   │   └── test_helper.exs                # excludes :integration
│   ├── config/{config,dev,prod,runtime,test}.exs
│   ├── mix.exs / mix.lock
│   └── Dockerfile
│
├── bun/                                   # 翻訳家 + 印鑑職人 (NATS-only, no HTTP; Bun runtime)
│   ├── services/fedify_service.ts         # ★ NATS Micro service
│   ├── handlers/                          # pure functions, no HTTP
│   │   ├── build/{note,follow,accept,announce,actor,dm,collection_op,…}.ts
│   │   ├── verify.ts                      # HTTP Signature verify
│   │   └── sign_delivery.ts               # HTTP Signature sign
│   ├── fedify/{context,keys,utils}.ts     # Fedify glue
│   ├── main.ts                            # legacy ap.* subscribes (being phased out)
│   ├── package.json                       # npm deps incl. `nats` → @nats-io/transport-node
│   ├── tsconfig.json
│   └── Dockerfile                         # oven/bun:1-alpine
│
├── api/                                   # ★ Mastodon/Misskey REST plugin (separate BEAM node)
│   ├── mix.exs                            # independent :sukhi_api app
│   ├── lib/sukhi_api/
│   │   ├── application.ex                 # start-up; prints registered routes
│   │   ├── capability.ex                  # @behaviour + `use` macro (auto-register)
│   │   ├── registry.ex                    # runtime discovery of capability modules
│   │   ├── router.ex                      # :rpc entry — handle(req) → {:ok, resp}
│   │   └── capabilities/                  # ← DROP FILES HERE TO ADD ENDPOINTS
│   │       └── mastodon_instance.ex       # example: GET /api/v1/instance
│   ├── config/{config,dev,prod,runtime,test}.exs
│   └── Dockerfile                         # distributed Erlang release
│
├── infra/
│   ├── nats/bootstrap.sh                  # JetStream stream bootstrap
│   ├── terraform/ · ansible/              # infra-as-code (OCI)
│
├── (observability stack removed — PromEx exposes /metrics, external scrape)
│
├── docker-compose.yml                     # dev stack
├── docker-compose.test.yml                # hermetic test stack
└── docs/ARCHITECTURE.md                   # ← this file
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

| Subject                            | Direction | Emitted by        | Consumed by                  |
| ---------------------------------- | --------- | ----------------- | ---------------------------- |
| `sns.outbox.note.created`          | pub       | `Notes`           | deliverer / timeline-updater |
| `sns.outbox.follow.requested`      | pub       | `Social`          | deliverer                    |
| `sns.outbox.like.created`          | pub       | (future)          | deliverer                    |
| `sns.events.timeline.home.updated` | pub       | timeline-updater  | streaming-fanout             |
| `sns.events.notification.mention`  | pub       | inbox handler     | streaming-fanout             |

### 4.3 NATS Micro services (Bun-side)

Service name: `fedify`, version `0.2.0`, queue group `fedify-workers`.
Multiple Bun replicas auto-share load.

| Endpoint              | Request                                    | Response                                 |
| --------------------- | ------------------------------------------ | ---------------------------------------- |
| `fedify.ping.v1`      | raw bytes                                  | echoes request (health check)            |
| `fedify.translate.v1` | `{object_type, payload}`                   | `{ok:true, data:{json_ld, ...}}`         |
| `fedify.sign.v1`      | `{actorUri, inbox, body, privateKeyJwk, keyId, algorithm?}` | `{ok:true, data:{headers:{...}}}` |
| `fedify.verify.v1`    | `{method, url, headers, body}`             | `{ok:true, data:{ok:bool, ...}}`         |

`object_type` values accepted by translate: `note`, `follow`, `accept`,
`announce`, `actor`, `dm`, `add`, `remove` (plus `integrity_proof` once
the pre-existing TS bug in `handlers/build/integrity_proof.ts:71` is
fixed in stage 5).

Service discovery: NATS Micro auto-publishes `$SRV.{PING,INFO,STATS}.fedify`.

### 4.4 Legacy NATS subjects (being phased out)

Old `ap.*` subscribe handlers still live in `deno/main.ts`. Elixir
callers progressively move to `SukhiFedi.Delivery.FedifyClient`. Once
all callers are migrated, `main.ts` subscribe loops are deleted (stage
2-b).

`db.*` subjects (Deno → Elixir DB queries) and `stream.new_post` (old
streaming publish) are on the same phase-out path — migrations live in
stages 3 (HTTP consolidation) and 2-b.

## 5. Transactional Outbox

The foundational correctness pattern. Without it, `DB insert + NATS pub`
is two independent writes and a crash between them loses or duplicates
events.

### 5.1 Schema

Migration `20260420000001_create_outbox.exs`:

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
index(outbox, [status, id])
index(outbox, [aggregate_type, aggregate_id])

-- AFTER INSERT trigger fires NOTIFY outbox_new so the relay wakes up immediately
```

Plus `delivery_receipts` (migration `20260420000002`):

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

All domain writes that need federation use `SukhiFedi.Outbox.enqueue_multi/6`
inside a single `Ecto.Multi` with the domain insert:

```elixir
Ecto.Multi.new()
|> Ecto.Multi.insert(:note, Note.changeset(%Note{}, attrs))
|> Outbox.enqueue_multi(:outbox_event,
     "sns.outbox.note.created", "note",
     & &1.note.id,
     fn %{note: note} -> %{note_id: note.id, ...} end)
|> Repo.transaction()
```

DB commit ⇒ outbox row is durable. Period.

Implemented call sites (grow as stages progress):
- `SukhiFedi.Notes.create_note/1`  → `sns.outbox.note.created`
- `SukhiFedi.Social.follow/2`      → `sns.outbox.follow.requested`
- *(future)* like / boost / delete once context fns exist.

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
5. Success → `status='published', published_at=now()`.
   Failure → `attempts++`, status flips to `failed` at 10.

## 6. End-to-end flows

### 6.1 Local user posts a Note

```
POST /api/v1/statuses
   │  (via proxy_plug → Deno api/notes during strangler-fig migration;
   │   direct Elixir handler after stage 3 completes)
   ▼
Elixir Notes.create_note/1
   Ecto.Multi:
     insert notes
     insert outbox(sns.outbox.note.created)
   commit  ──▶ AFTER INSERT TRIGGER fires NOTIFY outbox_new
                         │
                         ▼
              Outbox.Relay (wakes up)
                         │  Gnat.pub to JetStream OUTBOX
                         ▼
         (future consumer: ap-deliverer)
                         │  fan out to each follower inbox
                         ▼ (one Oban job per follower)
         Delivery.Worker (Oban)
          1. check delivery_receipts(activity_id, inbox_url) — skip if delivered
          2. build JSON-LD: FedifyClient.translate("note", payload)
          3. sign envelope: FedifyClient.sign(...)
          4. Req.post inbox_url
          5. on 2xx → insert delivery_receipt
          6. on non-2xx / error → Oban exp backoff, max 10 attempts
```

### 6.2 Remote server delivers to our inbox

```
POST /users/alice/inbox  (external Mastodon)
   │
   ▼
Elixir InboxController
   │   captures raw body + headers
   ▼
FedifyClient.verify({method, url, headers, body})
   │   NATS req/reply → fedify.verify.v1
   ▼
Deno handleVerify → Fedify.verifyRequest
   │   {ok: true} or {ok: false}
   ▼
Elixir Instructions.execute(activity)
   │   Follow / Accept / Create(Note) / Announce / Like / Delete
   ▼
DB writes + (sometimes) Outbox.enqueue for Accept back
   │
   ▼
200 OK
```

### 6.3 WebFinger (local actor lookup)

```
GET /.well-known/webfinger?resource=acct:alice@example.tld
   ▼
WebfingerController (Elixir, **no Deno call**)
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

### 6.5 /api/v1/timelines/home

Plain Ecto SELECT from the home-timeline view. No federation involved.
Not part of the refactor scope.

## 7. Observability (Elixir-native, OpenTelemetry-free)

- **Metrics**: `PromEx` exposes `/metrics` on port 4000. External
  scraper (self-hosted Prometheus on a larger box, Grafana Cloud Free,
  etc.) pulls from there. Out of the box: Ecto / Oban / Plug / BEAM
  system metrics; custom metrics via `:telemetry.execute` +
  `telemetry_metrics`.
- **Dashboards**: not provided in-repo. Point a Grafana instance
  (local or managed) at the Prometheus scraper that consumes
  `http://<host>:4000/metrics`. The gateway stack stays ~550 MB
  without an in-container Grafana/Prometheus.
- **Traces**: deliberately **not** instrumented. We rejected OpenTelemetry
  / Jaeger / otelcol because (a) the Deno / Fedify side's OTel support
  is expensive (needs `--unstable-otel`), (b) the operational tax doesn't
  pay off at our scale, and (c) structured logs with a `request_id`
  cover the replay-the-path use case. See `elixir/mix.exs` — zero
  `opentelemetry_*` deps.
- **Structured logging**: every controller / worker should log with
  `Logger.metadata(request_id: …)` so a single incident can be
  reconstructed via `grep`.

Custom metrics to emit as we build each stage:
| Metric                            | Type      | Where                |
| --------------------------------- | --------- | -------------------- |
| `sukhi_outbox_pending_count`      | gauge     | `Outbox.Relay` tick  |
| `sukhi_outbox_publish_rate`       | counter   | `Outbox.Relay`       |
| `sukhi_delivery_success_rate`     | counter   | `Delivery.Worker`    |
| `sukhi_delivery_failure_rate`     | counter   | `Delivery.Worker`    |
| `sukhi_fedify_latency_ms`         | histogram | `FedifyClient`       |
| `sukhi_inbox_request_rate`        | counter   | `InboxController`    |

## 8. Environment variables

| Var                        | Service  | Default                 | Purpose                            |
| -------------------------- | -------- | ----------------------- | ---------------------------------- |
| `DB_HOST` / `USER` / `PASS` / `NAME` | Elixir | (required in prod)  | Postgres connection                |
| `DB_POOL_SIZE`             | Elixir   | `10`                    | Ecto pool size                     |
| `NATS_HOST` / `NATS_PORT`  | Elixir   | `127.0.0.1:4222`        | NATS client                        |
| `NATS_URL`                 | Bun      | `nats://localhost:4222` | NATS client (both main.ts & svc)   |
| `DENO_URL`                 | Elixir   | `http://localhost:8000` | Legacy proxy target (phased out)   |
| `PORT`                     | Deno     | `8000`                  | Legacy HTTP server (phased out)    |
| `SUKHI_ROLE` *(planned)*   | Elixir   | `all`                   | `inbox` / `api` / `worker` / `all` |

## 9. Running locally

### Dev stack
```bash
docker-compose up -d        # postgres + nats + nats-bootstrap + elixir + bun + api
# http://localhost:4000            — Elixir gateway
# http://localhost:4000/metrics    — PromEx (scrape with external Prometheus)
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
# Elixir unit tests (no live deps, --no-start because app needs NATS):
cd elixir && mix test --no-start

# Elixir integration tests (needs docker-compose.test.yml up):
cd elixir && mix test --only integration

# Bun tests:
cd bun && bun test

# Type check the whole bun surface (tsc, invoked via bun):
cd bun && bun run check
```

## 10. Horizontal scale posture

- Both Elixir and Bun are designed to be **stateless** — all state is in
  Postgres or NATS. `mix release` + `docker compose up --scale gateway=N` adds Elixir
  replicas; identical Bun containers running the fedify service
  auto-load-balance via the NATS Micro queue group `fedify-workers`.
- The `Outbox.Relay`'s `FOR UPDATE SKIP LOCKED` makes running multiple
  relay instances safe — each claims a disjoint batch.
- ETS caches (WebFinger JRDs, remote actor fetches) are **node-local**;
  misses fall back to Postgres or a remote HTTP fetch, so cache
  inconsistency across nodes is harmless.
- Future `SUKHI_ROLE=inbox|api|worker|all` env switch lets a single
  image start with different supervision subtrees, so a node can
  specialize in e.g. inbox intake under DoS without affecting user API.

## 11. Migration philosophy (strangler-fig)

Refactor from the current mixed state to the target architecture in
small, always-mergeable, always-running steps. Stages 0–6 are the
checkpoints; every stage keeps `mix test` + `bun test` green and
can ship independently.

```
0   scaffolding            ✅ done
1   Outbox infra           ✅ done
2   NATS Micro (additive)  ✅ done
2-b remove old ap.*        ✅ FedifyClient-scope done; legacy ap.* subscribes still live
3   HTTP consolidation     ✅ WebFinger / NodeInfo / ActorFetcher / RateLimitPlug
3-b Deno HTTP removal      ✅ deno/{api.ts,api/,handlers/wellknown/} + proxy_plug deleted
3-c Plugin API (api/)      ✅ distributed-Erlang plugin node; capabilities auto-register
4   Delivery to Elixir     ✅ Worker uses FedifyClient + delivery_receipts
4-b Finch pool + E2E       ✅ Finch pool 50×4 per host; E2E blocked on Docker
5   God-module split       ✅ db_nats_listener 617 → 80 line dispatcher + 5 Nats.* modules
6   docs + dead-code purge ✅ 15 stale docs removed; README/CHECKLIST/INDEX point at this file
```

### §12 Plugin API node (distributed Erlang)

The Mastodon / Misskey REST surface runs as a **separate BEAM node** under
`api/`. The gateway reaches it with `:rpc.call/5`; no HTTP hop, no
JSON-over-NATS envelope, just Erlang distribution over the
docker-compose network.

```
client  ──HTTPS──▶  Elixir gateway (node gateway@elixir)
                    └─ router match "/api/v1/*_"
                       └─ SukhiFedi.Web.PluginPlug
                          └─ :rpc.call(api@api, SukhiApi.Router, :handle, [req])
                                           │
                                           ▼
                                   api BEAM node (node api@api)
                                   SukhiApi.Registry (auto-discovery)
                                     └─ Capabilities.MastodonInstance
                                     └─ Capabilities.…              ← one file = one feature
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
  use SukhiApi.Capability

  @impl true
  def routes, do: [{:get, "/api/v1/instance/peers", &peers/1}]

  def peers(_req), do: {:ok, %{status: 200, body: "[]", headers: [{"content-type", "application/json"}]}}
end
```

That's the entire change. No router edit, no manifest update — the
`use SukhiApi.Capability` macro persists a module attribute; `SukhiApi.Registry`
scans `:application.get_key(:sukhi_api, :modules)` at runtime and picks
up every such module.

**Removing** an endpoint — delete the file.

**Narrowing a node's surface** — set `ENABLED_CAPABILITIES` env to a
comma-separated list of module names (e.g. `Elixir.SukhiApi.Capabilities.MastodonInstance`).
Useful when running multiple specialised plugin nodes (e.g. a locked-down
admin-only node, or a public-facing read-only node).

**Failure modes**:

  * no `plugin_nodes` configured → 503 `{"error":"plugin_unavailable"}`
  * node unreachable at `:rpc` time → 503 `{"error":"plugin_rpc_failed"}`
  * handler crashes on the remote node → remote catches and returns 500
  * path not covered by any capability → remote returns 404

**Scale and isolation posture**:

  * multiple plugin nodes can run in parallel; `PluginPlug` picks the
    first reachable one each request
  * capabilities that need DB access call back to the gateway's context
    modules (`SukhiFedi.Notes`, `Accounts`, etc.) via `:rpc`, avoiding a
    second Ecto pool
  * an API surge crashes only the plugin node; gateway (federation /
    inbox / delivery) stays up

### Known 3-b regression

`/api/v1/*` and `/api/admin/*` used to be implemented in Deno. The
Deno HTTP layer was removed in 3-b and replaced by the plugin-node
pattern above in 3-c. The **`SukhiApi.Capabilities.MastodonInstance`
example is the only endpoint currently implemented** — porting the
remaining Mastodon/Misskey surface is an ongoing exercise in "drop
files into `capabilities/`", tackled feature by feature.

ActivityPub federation (inbox POST, WebFinger, NodeInfo, actor JSON,
outbound delivery) is **unaffected** — those paths stay on Elixir's
native handlers.

If you're adding a feature, first decide which stage it belongs in and
whether it should be deferred until the stage completes.
