# Sukhi Fedi - Minimal Fediverse Implementation
### Elixir + Deno (Fedify) — Native Scalability

> **Elixir is the courier. Deno is the craftsman.**

A minimal, scalable ActivityPub server that cleanly separates concerns:
- **Elixir** handles HTTP, delivery, queuing, and storage
- **Deno** handles ActivityPub logic, signing, and verification
- **NATS** is the single boundary between them

## Status

✅ **Priority 2**: Real-time Feeds & Streaming - COMPLETE  
✅ **Priority 3**: ActivityPub Federation - COMPLETE

## Quick Start

### Prerequisites
- Elixir 1.14+
- Deno 1.40+
- PostgreSQL 14+
- NATS Server

### Setup

```bash
# 1. Start dependencies
docker run -d -p 4222:4222 nats:latest
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:latest

# 2. Configure
cd elixir
cp config/dev.exs.example config/dev.exs  # Edit as needed

# 3. Setup database
mix deps.get
mix ecto.create
mix ecto.migrate

# 4. Start Deno worker
cd ../deno
deno run --allow-net --allow-env main.ts &

# 5. Start Elixir server
cd ../elixir
iex -S mix
```

### Test

```bash
# Test streaming
cd docs
./test_streaming.sh

# Test federation
./test_federation.sh
```

## Architecture

```
Internet → Elixir (HTTP) → NATS → Deno (ActivityPub) → NATS → Elixir (Storage)
                ↓
           PostgreSQL
                ↓
           Oban Queue → Delivery Workers
```

**Key Principles:**
- Elixir never parses ActivityPub semantics
- Deno never touches HTTP or storage
- NATS is the only boundary
- Signed JSON-LD is immutable

## Features

### Real-time Feeds & Streaming
- HTTP feeds (home, local)
- Server-Sent Events (SSE) streaming
- NATS-based pub/sub
- Sub-100ms latency

### ActivityPub Federation
- HTTP Signature verification
- Inbox/Outbox processing
- WebFinger discovery
- Actor profiles
- 15+ activity types supported
- Background delivery queue
- Automatic retries

### Supported Activities
- Follow (auto-accept)
- Create, Update, Delete
- Like, Announce (boost)
- Undo
- EmojiReact (Misskey)
- Accept, Reject
- Move, Block, Flag

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /.well-known/webfinger` | Actor discovery |
| `GET /users/:name` | Actor profile |
| `GET /users/:name/outbox` | Public activities |
| `POST /users/:name/inbox` | Receive activities |
| `GET /api/feeds/home` | Home feed |
| `GET /api/feeds/local` | Local feed |
| `GET /api/streaming/home` | Home feed (SSE) |
| `GET /api/streaming/local` | Local feed (SSE) |
| `POST /api/notes` | Create post |
| `POST /api/likes` | Like post |
| `POST /api/boosts` | Boost post |
| `POST /api/undo` | Undo activity |

## Documentation

📚 **[Complete Documentation Index](docs/INDEX.md)**

### Quick Links
- [Priority 2: Streaming](docs/PRIORITY_2_SUMMARY.md)
- [Priority 3: Federation](docs/PRIORITY_3_FEDERATION.md)
- [Federation Quick Reference](docs/FEDERATION_QUICKREF.md)
- [Deployment Guide](docs/FEDERATION_DEPLOYMENT.md)

## Project Structure

```
elixir/
├── lib/sukhi_fedi/
│   ├── web/          # HTTP controllers
│   ├── ap/           # NATS client & instructions
│   ├── delivery/     # Oban workers
│   ├── streaming/    # SSE & NATS listener
│   └── schema/       # Ecto schemas
└── priv/repo/migrations/

deno/
├── handlers/
│   ├── inbox.ts      # Activity processing
│   ├── verify.ts     # Signature verification
│   ├── like.ts       # Like activity builder
│   └── build/        # Activity builders
└── main.ts           # NATS subscriber

docs/                 # All documentation
```

## Scaling

**Single Node:**
- ~1,000 req/s inbox processing
- 10 concurrent delivery workers

**Scale Out:**
- Add Deno workers (NATS auto-distributes)
- Increase Oban concurrency
- Add PostgreSQL read replicas

## Configuration

```elixir
# config/config.exs
config :sukhi_fedi,
  domain: "your.domain.com"

config :sukhi_fedi, Oban,
  repo: SukhiFedi.Repo,
  queues: [delivery: 10]
```

## Requirements for Federation

⚠️ **HTTPS required** - Federation will not work over HTTP  
⚠️ **Valid domain** - Must have a real domain name

## Testing with Real Instances

1. Set up HTTPS and domain
2. Create account: `POST /api/accounts`
3. From Mastodon, search: `@username@your.domain.com`
4. Follow the account
5. Check: `SELECT * FROM follows;`

## Performance

- Sub-100ms feed queries
- ~1000 concurrent SSE connections per node
- Automatic retry with exponential backoff
- Persistent queue survives restarts

## Security

✅ HTTP Signature verification  
✅ Public key validation  
⚠️ Rate limiting (TODO)  
⚠️ Domain blocking (TODO)

## License

MPL-2.0

## Contributing

See [CHECKLIST.md](CHECKLIST.md) for implementation status.

---

**Built with:** Elixir • Deno • Fedify • NATS • PostgreSQL • Oban
