# Spoke: Hub-and-Spoke Server Platform - Architecture

<!--
==============================================================================
architecture.md - Spoke architecture reference
==============================================================================
Description: Complete Spoke architecture reference (living document)
Author: Matt Barham
Created: 2026-02-12
Modified: 2026-03-14
Version: 1.1.0
==============================================================================
Document Type: Reference
Audience: Developer, AI Assistant
Status: Active (living document)
==============================================================================
-->

## Overview

Spoke is a public, open-source hub-and-spoke server platform that lets anyone stand up a modular home server. The hub provides core orchestration (reverse proxy, auth, database, security). Modules are independent repos that plug in.

- **Spoke** = public platform framework (DNS/CDN-agnostic, no vendor lock-in)
- **Your Deployment** = your deployment instance of Spoke
- GitHub user: `captainzonks`, author: Matt Barham

## Repository Structure

```
spoke-deployment/                          (deployed instance — git repo: captainzonks/spoke)
├── Makefile                   # Orchestrator — always check first
├── modules.yml                # Module registry + site config (gitignored)
├── modules.yml.example        # Template with documentation
├── base.env.example           # Template for new instances
├── hub.env.example            # Hub env template
├── hub/                       # Core services
│   ├── docker-compose.yml     # socket-proxy, traefik, authentik, crowdsec, postgres-hub, redis
│   └── .env                   # Generated (gitignored)
├── modules/                   # Cloned module repos (all gitignored)
├── shared/env/                # Site-specific env (gitignored)
│   ├── base.env               # Instance config (SPOKE_DIR, DOMAIN, etc.)
│   └── hub.env                # Hub service versions and IPs
├── secrets/                   # All secrets (gitignored)
├── appdata/                   # Container persistent data (gitignored)
│   └── traefik/rules/         # Dynamic Traefik routing rules (hot-reload)
├── dockerfiles/               # Hub Dockerfiles only (traefik, crowdsec, postgres)
├── scripts/
│   ├── modules/               # Module management scripts
│   └── maintenance/           # Operational scripts
└── docs/                      # Project documentation
```

**Development repos** (separate from deployment):
- `/path/to/repos/spoke` — clean public clone (for hub development/PRs)
- `/path/to/repos/spoke-*` — individual module repos (for module development)

## Hub Services

| Service | Role |
|---------|------|
| socket-proxy | Docker API access (required by Traefik, isolated on soxy network) |
| traefik | Reverse proxy / gateway (the literal hub) |
| authentik + worker | Authentication / SSO |
| crowdsec | WAF / security engine |
| postgres-hub | Shared database (hub + module provisioned DBs) |
| redis | Shared cache |

## Module Inventory

### Infrastructure Modules (official — purpose-built for Spoke)

| Module | Repo | Services |
|--------|------|----------|
| monitoring | captainzonks/spoke-monitoring | grafana, prometheus, loki, telegraf, dozzle, alloy, nut-upsd |
| database | captainzonks/spoke-database | influxdb3, minio, couchdb, victoria-metrics |
| torrenting | captainzonks/spoke-torrenting | gluetun, qsticky, qbittorrent, slskd |
| plex | captainzonks/spoke-plex | plex, tautulli |
| music | captainzonks/spoke-music | picard, navidrome |
| protonmail | captainzonks/spoke-protonmail | protonmail-bridge |
| homepage | captainzonks/spoke-homepage | homepage |
| foundryvtt | captainzonks/spoke-foundryvtt | foundryvtt |
| immich | captainzonks/spoke-immich | immich-server, immich-ml, immich-postgres, immich-redis |
| adult | captainzonks/spoke-adult | dionysus, stash |

### Application Modules (official — use hub postgres)

| Module | Repo | Services |
|--------|------|----------|
| portfolio | captainzonks/spoke-portfolio | form-handler, oauth-proxy |
| trek | captainzonks/spoke-trek | trekker-app |

### External Modules (independent repos, standalone-first)

| Module | Repo | Services |
|--------|------|----------|
| genetics | captainzonks/GeneGnome | api-gateway, worker, frontend, postgres18, redis |

External modules have their own lifecycle and work standalone without Spoke. Spoke integrates them via `modules.yml` env_overrides and secrets_map. See `docs/external_modules.md` for the contract.

## Module Contract (stack.yml)

Each module repo includes a `stack.yml` that declares:
- Module metadata (name, version, description, author, license)
- Required networks and hub services
- Environment variables needed (from hub and module-specific)
- Secrets required
- Health check endpoints

## Environment & Secrets Strategy

### Env Merge Order

```
base.env ─────────────────────┐
hub.env ───────────────────────┤ → hub/.env (generated)
                               │
base.env ─────────────────────┐
module .env.example ───────────┤ → modules/{name}/.env (generated)
modules.yml env_overrides ─────┘   (last definition wins — modules.yml highest priority)
```

All three layers are written in order to the generated `.env`. Docker Compose uses the LAST definition of any variable, so `modules.yml` overrides always win. Duplicate variable entries in a generated `.env` are normal and expected.

### Gitignore Strategy

Committed (safe, no secrets):
- `base.env.example`, `hub.env.example`, `modules.yml.example`
- `hub/docker-compose.yml`
- All `modules/{name}/docker-compose.yml` (in their repos)

Gitignored (site-specific or contains secrets):
- `shared/env/base.env` — contains DOMAIN, personal paths
- `shared/env/hub.env` — hub service config
- `modules.yml` — personal domain, IPs, repo URLs
- `secrets/` — all secrets
- `modules/` — cloned module repos
- `appdata/` — runtime state
- `hub/.env`, `modules/{name}/.env` — generated files

### Docker Compose Override Files

Modules support site-specific `docker-compose.override.yml` files:
- Auto-detected by Docker Compose — no Makefile changes needed
- Gitignored — never committed to module repos
- Use for: extra volume mounts, CPU/memory limits, GPU passthrough
- Always check for override files before assuming `docker-compose.yml` is the complete config

## Docker Networks

| Network | Subnet | Purpose |
|---------|--------|---------|
| soxy | 192.168.33.0/24 | Docker socket proxy (isolated) |
| troxy | 192.168.35.0/24 | Main application network |
| auxy | 192.168.38.0/24 | Authentik auxiliary |

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make init` | Auto-detect system, create dirs, copy examples, create networks |
| `make hub-deploy` | Deploy hub services |
| `make hub-health` | Health check hub |
| `make hub-logs [SERVICE=svc] [SINCE=1h]` | Hub logs |
| `make module-sync [MODULE=name]` | Clone/pull module repos per modules.yml |
| `make deploy MODULE=name` | Validate + env gen + deploy module |
| `make rebuild MODULE=name [SERVICE=svc]` | Rebuild module/service |
| `make deploy-all` | Hub + all enabled modules |
| `make health MODULE=name` | Health check module |
| `make health-all` | Hub + all modules |
| `make logs MODULE=name [SERVICE=svc] [SINCE=1h]` | View logs |
| `make stop MODULE=name` | Stop module |
| `make down MODULE=name` | Stop and remove module |
| `make status` | Show all running containers |

**Key flags**: `FORCE_REGEN=true` (force .env regen), `NO_CACHE=true` (no build cache), `SERVICE=name` (target single service)

## Module Deployment Pipeline

The full module deployment pipeline (`make deploy MODULE=name`) runs these steps in order:

1. **Sync** (`sync_modules.sh`) — Clone or pull module repo per `modules.yml`
2. **Validate** (`validate_module.sh`) — Check stack.yml, required networks exist, secrets present
3. **Env Generate** (`generate_module_env.sh`) — Merge base.env + .env.example + modules.yml overrides → `.env`
4. **Hub Postgres** (`provision_hub_postgres.sh`) — Create databases/users if `hub_postgres` declared in stack.yml
5. **Traefik Deploy** (`deploy_traefik_rules.sh`) — Copy `traefik/*.yml` → `appdata/traefik/rules/mod_{name}_*`
6. **Traefik Audit** — Cross-reference `@file` references against all deployed definitions
7. **Compose Up** — `docker compose up -d` with the generated `.env`

## Related Documents

- `docs/external_modules.md` — External module contract
- `docs/docker_compose_structure_standards.md` — Compose file structure
- `docs/secrets_support.md` — Docker secrets support reference
- `docs/mcp_servers_reference.md` — MCP server configuration
- `CLAUDE.md` — Main project instructions (at repo root)
- `modules.yml.example` — Annotated modules.yml template
- `hub/docker-compose.yml` — Hub service definitions

---

**Document Version**: 1.1.0
**Last Updated**: 2026-03-14
**Author**: Matt Barham
**Host**: Your Server
