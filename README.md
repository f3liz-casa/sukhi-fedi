# sukhi-fedi

Federated SNS server. Mastodon/Misskey API compatible.
Elixir gateway + Bun/Fedify NATS Micro worker fleet, coordinated by
PostgreSQL + NATS JetStream.

## 📖 Documentation

**[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) is the canonical reference.**
A fresh contributor can rebuild the system from scratch using only that
document and the code. Read it first.

Additional reference material:

- [`docs/API_REFERENCE.md`](docs/API_REFERENCE.md) — REST endpoints
- [`docs/FEDERATION_QUICKREF.md`](docs/FEDERATION_QUICKREF.md) — ActivityPub cheatsheet
- [`docs/FEDERATION_DEPLOYMENT.md`](docs/FEDERATION_DEPLOYMENT.md) — production deployment
- [`docs/STREAMING.md`](docs/STREAMING.md) / [`docs/STREAMING_QUICKREF.md`](docs/STREAMING_QUICKREF.md) — WebSocket streaming
- [`docs/MVP.md`](docs/MVP.md) — product scope
- [`docs/INDEX.md`](docs/INDEX.md) — index of all docs

## Quick start

```bash
# Full dev stack (Postgres, NATS w/ JetStream, Elixir, Bun, api plugin)
docker-compose up -d
# → Elixir         http://localhost:4000
# → PromEx metrics http://localhost:4000/metrics  (scrape externally)
```

## Running tests

```bash
# Elixir unit tests (hermetic, no live deps)
cd elixir && mix test --no-start

# Bun tests
cd bun && bun test

# Type check (bun-agnostic via tsc)
cd bun && bun run check

# Integration tests (needs docker-compose.test.yml stack)
docker-compose -f docker-compose.test.yml up -d
cd elixir && mix test --only integration
```

## Architecture at a glance

| Layer      | Responsibility                                                      |
| ---------- | ------------------------------------------------------------------- |
| Elixir     | HTTP (Mastodon/Misskey API, inbox, WebFinger, NodeInfo), DB, Oban   |
| Bun        | NATS Micro service only — JSON-LD build, HTTP Signature, verify     |
| PostgreSQL | System of record, `outbox` table for exactly-once-effective events  |
| NATS       | JetStream `OUTBOX` + `DOMAIN_EVENTS`; Micro service `fedify`        |
| PromEx     | Prometheus metrics at `/metrics` (scrape externally; no Grafana in-repo) |

See §2 of `ARCHITECTURE.md` for the responsibility split rationale.

## License

AGPL-3.0-or-later. See `LICENSE`.
