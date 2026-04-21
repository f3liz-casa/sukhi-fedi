# sukhi-fedi

Federated SNS server. Mastodon/Misskey API compatible.
Elixir gateway + Elixir delivery node + Bun/Fedify NATS Micro worker
fleet + distributed-Erlang api plugin, coordinated by PostgreSQL +
NATS JetStream.

## 📖 Documentation

**[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) is the canonical reference.**
A fresh contributor can rebuild the system from scratch using only that
document and the code. Read it first.

- [`docs/ADDONS.md`](docs/ADDONS.md) — addon ABI contract (how to pick,
  write, or distribute feature addons)
- [`TODO.md`](TODO.md) — punch list of work deferred from the
  Mastodon-API MVP push; pick anything off it
- [`SETUP.md`](SETUP.md) — self-host deployment with docker compose + Watchtower

## Quick start

```bash
# Full dev stack (Postgres, NATS w/ JetStream, gateway, delivery, bun, api)
docker-compose up -d
# → Gateway         http://localhost:4000
# → Gateway metrics http://localhost:4000/metrics  (scrape externally)
# → Delivery metrics http://localhost:4001/metrics (scrape externally)
```

## Running tests

```bash
# Elixir gateway unit tests (hermetic, no live deps)
cd elixir && mix test --no-start

# Elixir delivery unit tests
cd delivery && mix test --no-start

# Bun tests
cd bun && bun test

# Type check (bun-agnostic via tsc)
cd bun && bun run check

# Integration tests (needs docker-compose.test.yml stack)
docker-compose -f docker-compose.test.yml up -d
cd elixir && mix test --only integration
```

## Architecture at a glance

| Layer      | Responsibility                                                           |
| ---------- | ------------------------------------------------------------------------ |
| Gateway    | HTTP ingress (Mastodon/Misskey API, inbox, WebFinger, NodeInfo), outbox writes |
| Delivery   | Outbox.Relay, Oban delivery & federation queues, outbound inbox POSTs    |
| Bun        | NATS Micro service only — JSON-LD build, HTTP Signature, verify          |
| PostgreSQL | System of record; shared `outbox` / `delivery_receipts` / `oban_jobs`    |
| NATS       | JetStream `OUTBOX` + `DOMAIN_EVENTS`; Micro service `fedify`             |
| PromEx     | Prometheus metrics at `/metrics` (gateway :4000, delivery :4001)         |

See §2 of `ARCHITECTURE.md` for the responsibility split rationale.

## License

AGPL-3.0-or-later. See `LICENSE`.
