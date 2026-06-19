# sukhi-fedi

Federated SNS server. Mastodon/Misskey API compatible.
Elixir gateway + Elixir delivery node + distributed-Erlang api plugin,
coordinated by PostgreSQL + NATS JetStream. ActivityPub translation
(JSON-LD, HTTP Signatures) runs natively in Elixir (`SukhiFedi.Fedi`); the
original Bun/Fedify NATS Micro worker is retired in production (v0.3.0) and
kept only for the dev stack and golden fixtures.

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
| Bun        | NATS Micro service (JSON-LD build, HTTP Signature, verify) — **retired in prod** (v0.3.0), now served natively by `SukhiFedi.Fedi`; dev stack & golden fixtures only |
| PostgreSQL | System of record; shared `outbox` / `delivery_receipts` / `oban_jobs`    |
| NATS       | JetStream `OUTBOX` + `DOMAIN_EVENTS`; Micro service `fedify`             |
| PromEx     | Prometheus metrics at `/metrics` (gateway :4000, delivery :4001)         |

See §2 of `ARCHITECTURE.md` for the responsibility split rationale.

## Fediverse software we learned from

sukhi-fedi didn't appear from nothing. It was shaped by the servers, clients,
and tools it sits next to — some we implement an API for, many we special-case
so federation round-trips cleanly, one we lean on as a library, and one just
lent us an idea. Listed honestly, by how we actually use them:

**Client API we implement**

- **Mastodon** — the Mastodon REST client API is sukhi-fedi's primary
  client-facing surface (`api/lib/sukhi_api/capabilities/mastodon_*.ex`,
  `docs/MASTODON_API.md`). Third-party clients and the bundled SPA both speak it.
- **Misskey** — federation is live; a native Misskey client API is mapped in
  `docs/MISSKEY_API.md` but not yet implemented.

**Third-party clients we accommodate**

These speak the Mastodon-compatible API, and the code carries small,
client-motivated accommodations so each stops erroring after login: permissive
CORS for the browser clients **Elk** / **Phanpy**, markers and discovery stubs
for **Ivory** / **Tusky** / **Moshidon**, strict-parser-safe (Gson) JSON for
**Moshidon**, and an OAuth consent-page CSP fix for **Toot!**. A Misskey client
API for **MissCat** / **Aria** is mapped in the docs but not yet built.

**Federation peers we tuned against**

Each taught us a wire quirk we now handle so activities survive the round trip:

- **Mastodon** — the baseline shape for outbound AP (LD-signature ordering,
  Secure Mode signed fetch).
- **Misskey** — custom-emoji reactions (carried as Like-with-content, which
  Misskey and Sharkey read), Misskey-Flavored-Markdown side channels, quote
  aliases (`quoteUrl` / FEP-e232), signed GETs.
- **hackers.pub** — a Fedify-based peer: long-form Articles, poll tallies it
  never sends `Update` for, RFC 9421 vs draft-cavage signatures, Ed25519
  object-integrity proofs (FEP-8b32).
- **Hollo** — another Fedify-based peer: RFC 9421 signing and object-integrity
  proofs. (Its `QuoteRequest` / FEP-044f flow is still a TODO — for now we fall
  back to legacy quote handling.)
- **Sharkey** / **Firefish** / **Fedibird** — the bare `RE:` / `QT:`
  quote-reference tail they append for Mastodon's sake, which we lift out when a
  quote card renders (plus Fedibird's nested `quote` shape).
- **Iceshrimp** — strict addressing (drops activities lacking `to`/`cc`) and
  reverse-webfinger from an actor URL.
- **Pleroma** / **Akkoma** — the cavage-12 signature set, and Pleroma's
  `EmojiReact` idiom, which we recognise on receive (we emit Like-with-content
  instead).
- **GoToSocial** — its JSON-LD namespace is vendored locally for canonicalization.

**Library we built on (now a reference)**

- **Fedify** (`@fedify/fedify`) — the ActivityPub toolkit the Bun worker was
  built on (its primitive layer: vocab classes, JSON-LD (de)serialization,
  HTTP-Signature sign/verify — not its framework). Production no longer runs it:
  the Elixir side (`SukhiFedi.Fedi.*`) serves all `fedify.*.v1` work natively,
  and the Bun worker is retired (v0.3.0) — kept as a rollback path and as the
  oracle that mints the byte-exact golden fixtures the native port is tested
  against. See `docs/FEDIFY.md`.

**An idea we borrowed**

- **Bonfire** — its *Circle* concept inspired sukhi-fedi's Circles (Lists
  generalized into the middle ground between following and forgetting). No
  Bonfire code is referenced here — just the shape of the idea.

## License

AGPL-3.0-or-later. See `LICENSE`.
