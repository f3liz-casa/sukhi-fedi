# Setup Guide

---

## Requirements

| Tool             | Version                        |
| ---------------- | ------------------------------ |
| Elixir           | ~> 1.16                        |
| OTP              | 26+ (bundled with Elixir 1.16) |
| Bun              | 1.x                            |
| PostgreSQL       | 16                             |
| NATS             | 2 (JetStream enabled)          |
| Docker + Compose | any recent version             |

---

## Quick Start (Docker Compose)

The fastest way to run the full stack locally.

```bash
docker compose up
```

Then run migrations:

```bash
docker compose exec elixir bin/sukhi_fedi eval 'SukhiFedi.Release.migrate()'
```

The app is available at `http://localhost:4000`.

To tear down including volumes:

```bash
docker compose down -v
```

---

## Local Development

### 1. Start backing services

```bash
# PostgreSQL + NATS only (skip observability stack for dev)
docker compose up postgres nats
```

### 2. Elixir

```bash
cd elixir
mix deps.get
mix ecto.create
mix ecto.migrate
iex -S mix
```

### 3. Bun

```bash
cd bun
bun install
bun run start
```

The `fedify` NATS Micro service connects to `nats://localhost:4222`
by default. It exposes endpoints `fedify.{ping,translate,sign,verify,inbox}.v1`
on the queue group `fedify-workers` — no HTTP listener.

---

## Environment Variables

### Elixir

| Variable                      | Description                 | Default (dev)           |
| ----------------------------- | --------------------------- | ----------------------- |
| `DB_HOST`                     | PostgreSQL host             | `localhost`             |
| `DB_USER`                     | PostgreSQL user             | `postgres`              |
| `DB_PASS`                     | PostgreSQL password         | `postgres`              |
| `DB_NAME`                     | Database name               | `sukhi_fedi`            |
| `DB_POOL_SIZE`                | Connection pool size        | `10`                    |
| `NATS_HOST`                   | NATS host                   | `127.0.0.1`             |
| `NATS_PORT`                   | NATS port                   | `4222`                  |
| `PORT`                        | HTTP listen port            | `4000`                  |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry collector URL | `http://localhost:4318` |

### Bun

| Variable          | Description                                    | Default (dev)           |
| ----------------- | ---------------------------------------------- | ----------------------- |
| `NATS_URL`        | NATS broker URL                                | `nats://localhost:4222` |
| `ENABLED_ADDONS`  | Comma list of enabled addon ids, or `all`      | `all`                   |
| `DISABLE_ADDONS`  | Comma list of disabled addon ids               | _(empty)_               |

---

## Ports

| Service                        | Port  | Exposure                       |
| ------------------------------ | ----- | ------------------------------ |
| Gateway (Elixir)               | 4000  | Public (incl. `/metrics`)      |
| Delivery metrics               | 4001  | Internal (`/metrics`)          |
| PostgreSQL                     | 5432  | Loopback only                  |
| NATS                           | 4222  | Internal                       |
| NATS HTTP API                  | 8222  | Internal                       |

---

## Database Migrations

Migrations live in `elixir/priv/repo/migrations/core/` (always-on) and
`elixir/priv/repo/migrations/addons/<id>/` (per-addon). The release
entrypoint (`elixir/rel/entrypoint.sh`) runs
`SukhiFedi.Release.migrate_all/0` automatically on every container
start, so Watchtower-driven upgrades apply new migrations without
operator intervention.

```bash
# Dev (walks core + all enabled addons' migration dirs)
cd elixir && mix sukhi.migrate

# Docker Compose (migrations run in the entrypoint; no manual step)
docker compose up -d

# One-off manual run
docker compose exec gateway bin/sukhi_fedi eval 'SukhiFedi.Release.migrate_all()'
```

---

## Observability

PromEx exposes Prometheus scrape endpoints inside each Elixir node:

- **Gateway** — `GET http://localhost:4000/metrics`
- **Delivery** — `GET http://localhost:4001/metrics`

Point any external Prometheus / Grafana / Jaeger stack at those
endpoints; the compose file does not bundle one.

---

## Production Deployment

Self-hosted flow: **Terraform** provisions the VM (cloud-init runs on first
boot to install Docker, mount the block volume, and harden the OS) →
**docker compose up -d** pulls pinned images from GHCR → **Watchtower** keeps
them fresh.

Two Terraform stacks available:

- `infra/terraform/` — ARM64 `VM.Standard.A1.Flex` (2 OCPU / 12 GB default)
- `infra/terraform-x64-freetier/` — x64 `VM.Standard.E2.1.Micro` (1 OCPU /
  1 GB, Always Free). Trades RAM for wider AD availability. See that
  directory's README for the memory-tight BEAM/PG tuning.

### Step 1 — Provision with Terraform

Creates the OCI VM, VCN/subnet, and a block volume mounted at `/mnt/data`
(used by PostgreSQL and NATS JetStream). cloud-init on first boot installs
Docker CE, creates the `deploy` user with your SSH key, locks down UFW
(SSH only; Cloudflare Tunnel handles HTTP ingress), tunes sysctl, and
creates a swap file on RAM-tight hosts.

```bash
cd infra/terraform                 # or infra/terraform-x64-freetier
cp terraform.tfvars.example terraform.tfvars
# fill in tenancy_ocid, user_ocid, fingerprint, private_key_path,
# tenancy_namespace, domain, etc.
terraform init
terraform apply
# outputs: instance_public_ip, ssh_command

# wait for cloud-init to finish (3–5 min on first boot)
ssh ubuntu@$(terraform output -raw instance_public_ip) 'cloud-init status --wait'
```

### Step 2 — Deploy with docker compose + Watchtower

Copy this repo (or the `sukhi-fedi-starter` skeleton) to the VM and set
`.env` with a version pin and any feature toggles:

```
SUKHI_REPO_OWNER=nyanrus
SUKHI_VERSION=v1            # :v1 for rolling minor updates, :v1.2.3 for pinned
DOMAIN=example.tld
ERLANG_COOKIE=<long random string>
ENABLED_ADDONS=all          # or a comma list: mastodon_api,streaming,moderation
ADDON_PRESETS=              # optional bundle: mastodon_compatible,server_version_watcher
WATCHTOWER_POLL_INTERVAL=3600
```

Then:

```bash
docker compose pull
docker compose up -d
```

Migrations run inside the `gateway` entrypoint on every start, so first
boot and subsequent upgrades are symmetric.

### Upgrades

Nothing to do. Watchtower polls GHCR every `WATCHTOWER_POLL_INTERVAL`
seconds, pulls the new image when the `:v1` / `:v1.2` / `:v1.2.3` tag
you pinned moves, and recreates `gateway` / `api` / `bun` containers.
Stateful `postgres` / `nats` containers are left alone.

To force an upgrade immediately:

```bash
docker compose pull gateway api bun
docker compose up -d gateway api bun
```

To pin a specific version (opt out of auto-update):

```bash
# in .env
SUKHI_VERSION=v1.2.3
```

### Logs

```bash
docker compose logs -f gateway
docker compose logs -f bun api
```

---

## Scaling Bun Workers

NATS Micro queue-groups the Bun fleet on `fedify-workers`, so adding
replicas is automatic:

```bash
docker compose up -d --scale bun=3
```
