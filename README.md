# sukhi-fedi

Federated SNS server. Mastodon/Misskey API compatible.
Elixir gateway + Bun/Fedify NATS Micro worker fleet, coordinated by
PostgreSQL + NATS JetStream.

## 📖 Documentation

**[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) is the canonical reference.**
A fresh contributor can rebuild the system from scratch using only that
document and the code. Read it first.

- [`docs/ADDONS.md`](docs/ADDONS.md) — addon ABI contract (how to pick,
  write, or distribute feature addons)
- [`SETUP.md`](SETUP.md) — self-host deployment with docker compose + Watchtower

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
