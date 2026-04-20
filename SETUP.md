# Setup Guide

---

## Requirements

| Tool             | Version                        |
| ---------------- | ------------------------------ |
| Elixir           | ~> 1.16                        |
| OTP              | 26+ (bundled with Elixir 1.16) |
| Deno             | 2.3.1                          |
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

### 3. Deno

```bash
cd deno
deno install
deno task start
```

Deno connects to NATS at `nats://localhost:4222` by default and listens on port
`8000`.

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

### Deno

| Variable                      | Description                 | Default (dev)           |
| ----------------------------- | --------------------------- | ----------------------- |
| `NATS_URL`                    | NATS broker URL             | `nats://localhost:4222` |
| `PORT`                        | HTTP listen port            | `8000`                  |
| `OTEL_DENO`                   | Enable OpenTelemetry        | `1`                     |
| `OTEL_SERVICE_NAME`           | Service name in traces      | `sukhi-fedi-deno`       |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry collector URL | `http://localhost:4318` |

---

## Ports

| Service                        | Port  | Exposure                       |
| ------------------------------ | ----- | ------------------------------ |
| Elixir web                     | 4000  | Public                         |
| Deno HTTP                      | 8000  | Internal only (Docker network) |
| PostgreSQL                     | 5432  | Loopback only                  |
| NATS                           | 4222  | Internal                       |
| NATS HTTP API                  | 8222  | Internal                       |
| OpenTelemetry collector (OTLP) | 4318  | Internal                       |
| Jaeger UI                      | 16686 | Loopback only                  |
| Prometheus                     | 9090  | Loopback only                  |
| Grafana                        | 3000  | Loopback only                  |

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

The Docker Compose stack includes a full observability setup:

- **Jaeger** — distributed traces at `http://localhost:16686`
- **Prometheus** — metrics at `http://localhost:9090`
- **Grafana** — dashboards at `http://localhost:3000`

Elixir exposes a Prometheus scrape endpoint at `GET /metrics`.

Deno emits OTLP traces when `OTEL_DENO=1` and `--unstable-otel` is passed
(included in `deno task start`).

---

## Production Deployment

Self-hosted flow: **Terraform** provisions the VM → **Ansible**
configures it → **docker compose up -d** pulls pinned images from GHCR
→ **Watchtower** keeps them fresh.

### Step 1 — Provision with Terraform

Creates the OCI VM (ARM64 `VM.Standard.A1.Flex`), VCN/subnet, and a
block volume mounted at `/mnt/data` (used by PostgreSQL and NATS JetStream).

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# fill in tenancy_ocid, user_ocid, fingerprint, private_key_path,
# tenancy_namespace, domain, etc.
terraform init
terraform apply
# outputs: instance_public_ip
# also generates: infra/ansible/inventory.ini
```

### Step 2 — Configure with Ansible

Mounts the block volume, creates the `deploy` user, and installs Docker.

```bash
cd infra/ansible
ansible-galaxy collection install community.general ansible.posix
# update inventory.ini with the IP from terraform output
ansible-playbook -i inventory.ini playbook.yml
```

### Step 3 — Deploy with docker compose + Watchtower

Copy this repo (or the `sukhi-fedi-starter` skeleton) to the VM and set
`.env` with a version pin and any feature toggles:

```
SUKHI_REPO_OWNER=nyanrus
SUKHI_VERSION=v1            # :v1 for rolling minor updates, :v1.2.3 for pinned
DOMAIN=example.tld
ERLANG_COOKIE=<long random string>
ENABLED_ADDONS=all          # or a comma list: mastodon_api,streaming,moderation
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
