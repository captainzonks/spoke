# Spoke: Module Development Guide

<!--
==============================================================================
module_development.md - How to create a Spoke module
==============================================================================
Description: Complete guide for developing official and external Spoke modules
Author: Matt Barham
Created: 2026-03-23
Version: 1.0.0
==============================================================================
Document Type: Guide
Audience: Module Developer
Status: Active
==============================================================================
-->

## Overview

A Spoke module is a self-contained service group packaged as a Git repository. Modules are cloned into `modules/{name}/` and deployed through the standard pipeline:

```
make module-sync MODULE=name    # Clone/pull repo
make deploy MODULE=name         # env gen -> validate -> traefik deploy -> compose up
```

This guide covers everything needed to create a module from scratch.

## Module Types

| Type | Repo Naming | Designed For Spoke | Network Naming |
|------|------------|-------------------|----------------|
| **Official** | `spoke-{name}` | Yes | Uses `troxy` directly |
| **External** | Any | Standalone-first | Uses `${PROXY_NETWORK}` |

Official modules are purpose-built for Spoke. External modules are independent repos that work standalone and are adapted via `modules.yml` overrides. See [external_modules.md](external_modules.md) for the external module contract.

## Required Files

### 1. `docker-compose.yml`

The compose file defines all services in the module.

**Key requirements:**
- Services accept configuration via environment variables
- Build contexts use relative paths (repo is cloned into `modules/{name}/`)
- External networks reference hub networks by name
- All internal networks include explicit `name:` fields (prevents Docker Compose project-name prefixing)

**Example structure:**

```yaml
############################
#### NETWORKS
############################

networks:
  troxy:
    external: true
    name: troxy

############################
#### SECRETS
############################

secrets:
  db_password:
    file: ${SECRETS_DIR}/mymodule/db_password

############################
#### SERVICES
############################

services:
  #====================================
  # MYSERVICE - Brief description
  #====================================
  myservice:
    container_name: myservice
    image: ${MYSERVICE_IMAGE}
    restart: unless-stopped
    user: ${PUID}:${DGID}
    networks:
      troxy:
        ipv4_address: ${MYSERVICE_IP}
    environment:
      - TZ=${TZ}
      - DOMAIN=${DOMAIN}
    secrets:
      - db_password
    volumes:
      - ${APPDATA_DIR}/mymodule:/config
```

**Hub networks available to modules:**

| Network | Purpose | When to Use |
|---------|---------|-------------|
| `troxy` | Traefik proxy network | Services exposed via Traefik |
| `soxy` | Socket-proxy network | Services needing Docker API access |
| `auxy` | Authentik auxiliary network | Services using Authentik forward auth |

### 2. `.env.example`

Module-specific defaults. This file is the second layer in the 3-layer env merge:

```
base.env (hub-wide) + .env.example (module defaults) + modules.yml overrides (site-specific)
```

**Format:**

```bash
# ==============================================================================
# Module Name - Environment Configuration
# ==============================================================================
# Description: Default configuration for module-name
# ==============================================================================

#### Service Configuration
MYSERVICE_IMAGE=org/image:1.2.3
MYSERVICE_IP=172.21.X.Y
MYSERVICE_PORT=8080
```

**Rules:**
- Use `VAR=value` format (no quotes, no `export`)
- Hub variables (`TZ`, `DOMAIN`, `PUID`, etc.) are provided by `base.env` — do not redefine them here
- Use specific image version tags, never `latest` (exceptions: images that genuinely have no versioned tags)
- Include comments explaining non-obvious variables

### 3. `stack.yml` — Module Manifest

The manifest declares module metadata, requirements, and health checks. Used by `validate_module.sh` before deployment.

```yaml
module:
  name: mymodule
  version: "1.0.0"
  description: "Brief description of what this module provides"
  author: "Your Name"
  license: MIT

requires:
  networks:
    - name: troxy
      required: true
    - name: soxy
      required: false
  hub_services:
    - traefik

env:
  hub:
    # Variables provided by base.env (validated at deploy time)
    - TZ
    - DOMAIN
    - SPOKE_DIR
    - SECRETS_DIR
    - APPDATA_DIR
    - PUID
    - DGID
  module:
    # Variables defined in .env.example
    - MYSERVICE_IMAGE
    - MYSERVICE_IP
    - MYSERVICE_PORT

secrets:
  - name: db_password
    required: true
  - name: api_key
    required: false

health:
  - service: myservice
    path: /health
    port: 8080
```

**Fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `module.name` | Yes | Module identifier (matches directory name) |
| `module.version` | Yes | Semantic version |
| `module.description` | Yes | One-line description |
| `module.author` | Yes | Author name |
| `module.license` | Yes | License identifier (e.g., `MIT`) |
| `requires.networks` | Yes | Docker networks the module needs |
| `requires.hub_services` | No | Hub services the module depends on |
| `env.hub` | Yes | Hub variables consumed (validated against `base.env`) |
| `env.module` | Yes | Module-specific variables (defined in `.env.example`) |
| `secrets` | No | Docker secrets the module uses |
| `health` | No | HTTP health check endpoints per service |

### 4. `traefik/` — Routing Rules (Optional)

For web-accessible services, provide Traefik dynamic configuration files:

```
traefik/
├── routers_mymodule.yml      # HTTP router definitions
├── services_mymodule.yml     # Load balancer service definitions
└── middlewares_mymodule.yml   # Module-specific middleware (optional)
```

During deployment, `deploy_traefik_rules.sh` copies these to `appdata/traefik/rules/` with a `mod_` prefix (e.g., `mod_routers_mymodule.yml`). Traefik auto-detects new files without restart.

**Router example (`traefik/routers_mymodule.yml`):**

```yaml
http:
  routers:
    mymodule:
      rule: "Host(`mymodule.{{ env \"DOMAIN\" }}`)"
      entryPoints:
        - websecure
      service: mymodule
      tls: {}
      middlewares:
        - mymodule-headers
```

**Service example (`traefik/services_mymodule.yml`):**

```yaml
http:
  services:
    mymodule:
      loadBalancer:
        servers:
          - url: "http://myservice:8080"
```

**Rules:**
- Use Go template `{{ env "DOMAIN" }}` for domain references
- Hub security middleware (CrowdSec, Authentik) is added by the operator per deployment, not in the module
- Module-specific middleware (headers, rate limits) belongs in the module's `middlewares_*.yml`
- File names must be unique across all modules (the `mod_` prefix helps, but avoid generic names)

## Directory Structure

A complete module looks like:

```
spoke-mymodule/
├── docker-compose.yml       # Service definitions
├── .env.example             # Module defaults
├── stack.yml                # Module manifest
├── traefik/                 # Traefik rules (optional)
│   ├── routers_mymodule.yml
│   └── services_mymodule.yml
├── LICENSE                  # MIT license
└── README.md                # Module documentation
```

## Environment Variable Flow

Understanding the 3-layer merge is essential:

```
Layer 1: shared/env/base.env          (instance-wide: DOMAIN, TZ, PUID, DGID, etc.)
Layer 2: modules/{name}/.env.example  (module defaults: images, IPs, ports)
Layer 3: modules.yml env_overrides    (site-specific: custom IPs, paths, overrides)
         ↓
All three written IN ORDER to modules/{name}/.env
Docker Compose uses the LAST definition → Layer 3 always wins
```

**Duplicate entries in `.env` are normal.** The same variable may appear in both `base.env` and `.env.example` — the last occurrence wins.

**Module-specific variables** (image tags, IPs, ports) belong in `.env.example`. They are not defined in `base.env`. To override them site-specifically, use `modules.yml` `env_overrides`.

## modules.yml Registration

Every module needs an entry in the deployment's `modules.yml`:

```yaml
modules:
  mymodule:
    repo: "git@github.com:captainzonks/spoke-mymodule.git"
    ref: "main"
    enabled: true
    env_overrides:
      # Site-specific overrides (optional)
      MYSERVICE_IP: "172.21.5.10"
    secrets_map:
      db_password: "secrets/mymodule/db_password"
```

See `modules.yml.example` in the hub repo for the full template with documentation.

## Deployment Pipeline

When you run `make deploy MODULE=mymodule`:

1. **Env Generation** (`generate_module_env.sh`): Merges `base.env` + `.env.example` + `modules.yml` overrides into `modules/{name}/.env`
2. **Validation** (`validate_module.sh`): Checks `stack.yml` requirements — networks exist, hub services running, secrets present
3. **Traefik Deployment** (`deploy_traefik_rules.sh`): Copies `traefik/` rules to `appdata/traefik/rules/mod_*`, audits for missing middleware/service references
4. **Compose Up**: Runs `docker compose up -d` in the module directory

## Docker Secrets

Secrets are mounted as files, not environment variables:

```yaml
# In docker-compose.yml
secrets:
  db_password:
    file: ${SECRETS_DIR}/mymodule/db_password

services:
  myservice:
    secrets:
      - db_password
    environment:
      - DB_PASSWORD_FILE=/run/secrets/db_password
```

**Container-specific patterns** (how services read secrets):

| Pattern | Example | Used By |
|---------|---------|---------|
| `_FILE` suffix | `POSTGRES_PASSWORD_FILE=/run/secrets/...` | PostgreSQL |
| `file:///` prefix | `AUTHENTIK_SECRET_KEY=file:///run/secrets/...` | Authentik |
| `GF_VAR__FILE` | `GF_DATABASE_PASSWORD__FILE=/run/secrets/...` | Grafana |
| `FILE__VAR` prefix | `FILE__DB_PASS=/run/secrets/...` | LinuxServer.io images |

Secret file paths in compose reference `${SECRETS_DIR}`. The actual mapping to host paths is done in `modules.yml` `secrets_map`.

## Conventions

### Naming

- **Repo**: `spoke-{name}` for official modules
- **Container names**: Short, descriptive (e.g., `grafana`, `prometheus`, `plex`)
- **Network keys**: Match hub network names (`troxy`, `soxy`, `auxy`)
- **Secret names**: `{service}_{secret_type}` (e.g., `grafana_admin_password`)
- **Traefik files**: `{type}_{modulename}.yml` (e.g., `routers_monitoring.yml`)
- **File naming**: Underscores, not hyphens (e.g., `my_script.sh`, not `my-script.sh`)

### Security

- Run containers as non-root when the image supports it: `user: "${PUID}:${DGID}"`
- Drop all capabilities and add back only what's needed
- Use `read_only: true` when the container supports it
- Mount secrets via Docker secrets, not environment variables
- Never hardcode passwords or tokens in compose files

### Compose File Standards

Follow the structure standards documented in [docker_compose_structure_standards.md](docker_compose_structure_standards.md):

- Section order: NETWORKS -> VOLUMES -> SECRETS -> SERVICES
- Section separators: `####` format (28-29 chars)
- Service separators: `#======` (38 chars)
- Single-line service comments: `# SERVICE_NAME - Brief description`
- Environment format: `VAR=${VAR}` (no quotes)

## README Template

Every module should include a README with:

```markdown
# spoke-{name}

Brief description of what this module provides.

## Services

| Service | Image | Description |
|---------|-------|-------------|
| service-name | `org/image:tag` | What it does |

## Prerequisites

- Spoke hub running (traefik, postgres-hub, etc.)
- Required secrets created (list them)

## Quick Start

1. Add module to `modules.yml` (see example below)
2. `make module-sync MODULE={name}`
3. Create required secrets in `secrets/{name}/`
4. `make deploy MODULE={name}`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VAR_NAME` | `default` | What it configures |

## References

- [Upstream Project](https://example.com)
- [Docker Hub Image](https://hub.docker.com/r/org/image)
```

## Testing Your Module

Before submitting:

1. **Validate manifest**: `make validate MODULE=mymodule`
2. **Deploy**: `make deploy MODULE=mymodule`
3. **Health check**: `make health MODULE=mymodule`
4. **Logs**: `make logs MODULE=mymodule SINCE=5m`
5. **Verify Traefik**: Check `appdata/traefik/rules/` for `mod_*` files with correct content
6. **Test access**: Verify the service is reachable through Traefik

## Further Reading

- [architecture.md](architecture.md) — Full Spoke architecture reference
- [external_modules.md](external_modules.md) — External module integration contract
- [architecture_decisions.md](architecture_decisions.md) — Key design decisions and rationale
- [docker_compose_structure_standards.md](docker_compose_structure_standards.md) — Compose file formatting
- [secrets_support.md](secrets_support.md) — Docker secrets reference per service
