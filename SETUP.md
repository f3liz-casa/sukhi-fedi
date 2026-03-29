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

```bash
# Dev
cd elixir && mix ecto.migrate

# Docker Compose
docker compose exec elixir bin/sukhi_fedi eval 'SukhiFedi.Release.migrate()'

# Production (Kamal)
kamal app exec --interactive --reuse "bin/sukhi_fedi eval 'SukhiFedi.Release.migrate()'"
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

Deployment is three steps: **Terraform** provisions the OCI server → **Ansible**
configures it → **Kamal** deploys the app.

### Step 1 — Provision with Terraform

Terraform creates the OCI VM (ARM64 `VM.Standard.A1.Flex`), VCN/subnet, and a
block volume mounted at `/mnt/data` (used by PostgreSQL and NATS JetStream).

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# fill in tenancy_ocid, user_ocid, fingerprint, private_key_path,
# tenancy_namespace, domain, etc.
terraform init
terraform apply
# outputs: instance_public_ip
# also generates: infra/ansible/inventory.ini, config/deploy.yml, config/deploy_deno.yml
```

### Step 2 — Configure with Ansible

Ansible mounts the block volume, creates the `deploy` user, and installs Docker.

```bash
cd infra/ansible
ansible-galaxy collection install community.general ansible.posix
# update inventory.ini with the IP from terraform output
ansible-playbook -i inventory.ini playbook.yml
```

### Step 3 — Deploy with Kamal

#### Prerequisites

- OCI Container Registry (OCIR) credentials
- Cloudflare Tunnel token
- Server SSH access as the `deploy` user

### Secrets

Copy and fill in `.kamal/secrets`:

```
OCIR_USERNAME=<tenancy-namespace>/<oci-username>
OCIR_AUTH_TOKEN=<oci-auth-token>
TUNNEL_TOKEN=<cloudflare-tunnel-token>
POSTGRES_USER=sukhi
POSTGRES_PASSWORD=<strong-random-password>
GF_SECURITY_ADMIN_PASSWORD=<grafana-admin-password>
```

### First deployment

```bash
# Build and push the Deno image separately (it's an accessory)
kamal build push --config-file config/deploy_deno.yml

# Bootstrap the server
kamal setup

# Start accessories in order
kamal accessory boot postgres
kamal accessory boot nats
kamal accessory boot deno
kamal accessory boot otelcol
kamal accessory boot jaeger
kamal accessory boot prometheus
kamal accessory boot grafana
kamal accessory boot cloudflared

# Run migrations
kamal app exec --interactive --reuse "bin/sukhi_fedi eval 'SukhiFedi.Release.migrate()'"
```

### Subsequent deployments

```bash
kamal deploy
```

To update Deno independently:

```bash
kamal build push --config-file config/deploy_deno.yml
kamal accessory reboot deno
```

### Logs

```bash
kamal app logs
kamal accessory logs deno
```

---

## Adding Deno Workers

To scale AP processing, add more Deno workers. NATS distributes the queue
automatically — no config changes required:

```bash
# Docker Compose
docker compose up --scale deno=3

# Kamal — update replicas in config/deploy.yml, then:
kamal deploy
```
