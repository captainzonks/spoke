# External Module Contract

<!--
==============================================================================
external_modules.md - Spoke external module contract
==============================================================================
Description: How Spoke handles externally-managed repos
Author: Matt Barham
Created: 2026-02-14
Modified: 2026-09-27
Version: 1.1.0
==============================================================================
Document Type: Reference
Audience: Module Developer
Status: Final
==============================================================================
-->

## Overview

External modules are repos that exist independently of Spoke — they have their own lifecycle, releases, and can run standalone without Spoke. Spoke integrates them by cloning into `modules/{name}/` and applying environment overrides and secret mappings.

This document defines the contract between Spoke and external repos.

## Minimum Contract (must have)

Every external module **must** provide:

### 1. `docker-compose.yml`

- Services accept configuration via environment variables
- Build contexts use **relative paths** (repo is cloned into `modules/{name}/`)
- External proxy network uses a configurable name:
  ```yaml
  networks:
    proxy:
      external: true
      name: ${PROXY_NETWORK:-proxy}
  ```
  Spoke sets `PROXY_NETWORK=troxy` via env override. Standalone defaults to `proxy`.

### 2. `.env.example`

- Module-specific defaults (image tags, ports, IPs, service config)
- Hub variables (TZ, DOMAIN, PUID, etc.) included with standalone defaults
- Clearly marked: hub variables are overridden by Spoke's `base.env`

## Full Integration (recommended)

For full Spoke pipeline support, also provide:

### 3. `stack.yml` — Module Manifest

Enables validation, health checks, and hub service provisioning:

```yaml
module:
  name: module-name
  version: "1.0.0"
  description: "Brief description"

requires:
  networks:
    - name: troxy
      required: true
  hub_services:
    - traefik

env:
  hub:
    - TZ, DOMAIN, SPOKE_DIR, SECRETS_DIR, APPDATA_DIR
    # ... variables provided by base.env
  module:
    - MODULE_SPECIFIC_VAR
    # ... variables defined in .env.example

secrets:
  - name: secret_name
    path: category/secret_file
    required: true

health:
  - service: container-name
    path: /health
    port: 8080
```

If the module uses its own database (not hub postgres), omit the `hub_postgres` section.

### 4. `traefik/` — Routing Rules

Traefik dynamic configuration files for web-accessible services:

- `traefik/routers_{name}.yml` — HTTP router definitions
- `traefik/services_{name}.yml` — Load balancer service definitions
- `traefik/middlewares_{name}.yml` — Module-specific middleware (optional)

Rules should be **self-contained** — define all middleware chains locally so the module works with any Traefik deployment. Hub security middleware (CrowdSec, Authentik) can be appended by the operator per deployment.

## Key Adaptation Patterns

### Network Mapping

External repos may name their proxy network differently (`proxy`, `nginx-proxy`, `web`). The `name:` property maps the internal key to the actual Docker network:

```yaml
networks:
  proxy:
    external: true
    name: ${PROXY_NETWORK:-proxy}  # Spoke sets PROXY_NETWORK=troxy
```

This keeps the compose file's internal references unchanged while mapping to the correct Docker network.

### Path Variables

External repos should use these variables for portable paths:

| Variable | Standalone Default | Spoke Value |
|----------|-------------------|-------------|
| `SECRETS_DIR` | `./secrets` | Set by Spoke (absolute path) |
| `IMAGE_PREFIX` | repo-specific (e.g., `genegnome`) | Instance name (e.g., `myserver`) |
| `PROXY_NETWORK` | `proxy` | `troxy` |

Module-specific variables (e.g., `GENETICS_ENCRYPTED_DIR`) use the module's own naming conventions. Site-specific overrides go in `modules.yml` `env_overrides`.

### Build Contexts

Use relative paths — the module is cloned into `modules/{name}/`:

```yaml
build:
  context: ./            # Repo root (for workspace builds)
  dockerfile: sub-dir/Dockerfile
```

### Module-Internal Networks

Networks defined inside `docker-compose.yml` as non-external require no changes. They are scoped to the module's compose project.

### Secret Mapping

Compose declares secrets with `${SECRETS_DIR}` paths:

```yaml
secrets:
  db_password:
    file: ${SECRETS_DIR}/category/secret_file
```

Spoke's `secrets_map` in `modules.yml` maps compose secret names to actual file paths on the host:

```yaml
modules:
  module-name:
    secrets_map:
      db_password: "secrets/category/secret_file"
```

## Versioning

Modules are versioned with [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html), released as signed `vX.Y.Z` tags with a `CHANGELOG.md` ([Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/)). Hub ADR-029 has the full policy.

A module's public API, for versioning purposes, is its contract with the deployment:

- variable names in `.env.example`
- secret names the compose file expects (the `secrets_map` keys)
- service, container and network names
- volume and appdata layout
- hub services and `modules.yml` keys it needs

| Bump | When |
|------|------|
| MAJOR | Something in the contract is removed or renamed, or upgrading needs a manual step (data migration, a new secret to create, a `modules.yml` edit) |
| MINOR | Something is added that existing deployments can ignore: a new service, an optional variable, a feature |
| PATCH | Fixes, and upstream image bumps that leave the contract unchanged |

Below `1.0.0` a breaking change bumps MINOR.

Version fields inside the repo must equal the release. `scripts/maintenance/release.sh prepare` in the hub sets them all in the release commit:

- `stack.yml` `module.version`
- `Cargo.toml`, `pyproject.toml` and `package.json` versions, in the repo root and its immediate subdirectories
- the `.env.example` keys listed on a `# @release-version:` comment, for tags of images the repo builds itself:

  ```bash
  # @release-version: MYAPP_API_TAG MYAPP_WORKER_TAG
  MYAPP_API_TAG=1.4.0
  MYAPP_WORKER_TAG=1.4.0
  ```

The per-file header `Version:` fields are file revisions and are not tied to releases.

## modules.yml Entry

Register external modules in `modules.yml`. Pin `ref` to a release tag; `make module-sync` then checks out exactly that release (detached, no pull). A branch name such as `main` still works and tracks the branch.

```yaml
modules:
  module-name:
    repo: "git@github.com:org/repo.git"
    ref: "v1.2.0"
    enabled: true
    env_overrides:
      PROXY_NETWORK: "troxy"
      IMAGE_PREFIX: "myserver"
      # Site-specific overrides...
    secrets_map:
      secret_name: "secrets/category/secret_file"
```

## Spoke Pipeline

External modules go through the same pipeline as official modules:

```
make module-sync MODULE=name    # Clone/pull repo to modules/{name}/
make deploy MODULE=name         # env gen → validate → traefik deploy → compose up
```

1. **Sync**: Clones repo to `modules/{name}/`, then checks out the release tag in `ref` (or pulls the branch in `ref`)
2. **Env Gen**: Merges `base.env` + `.env.example` + `env_overrides` → `.env`
3. **Validate**: Checks `stack.yml` requirements (networks, hub services, secrets)
4. **Traefik Deploy**: Copies `traefik/` rules to `appdata/traefik/rules/mod_*`
5. **Compose Up**: Runs `docker compose up -d` in module directory

## Examples

### GeneGnome (genetics)

First external module. Characteristics:
- Public repo with own release lifecycle (semver tags, per ADR-029)
- Own PostgreSQL 18 instance (not hub postgres)
- Internal isolated networks (no external access for processor)
- LUKS-encrypted volumes for data storage
- Multiple custom-built Rust services

See: [captainzonks/GeneGnome](https://github.com/captainzonks/GeneGnome)

### Daggerheart (on hold)

Simpler external module (1 container, no internal networks, no own database). Will be adapted when functional.

## Differences from Official Modules

| Aspect | Official Module | External Module |
|--------|----------------|-----------------|
| Repo ownership | `spoke-{name}` | Independent repo |
| Designed for Spoke | Yes | Standalone-first |
| Network naming | Uses `troxy` directly | Uses `${PROXY_NETWORK}` |
| Hub variables | Not in `.env.example` | Included with defaults |
| Build contexts | Relative (always) | Must be made relative |
| Release cycle | Tied to Spoke | Independent |
