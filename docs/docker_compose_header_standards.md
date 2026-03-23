# Docker Compose Header Standards

<!--
==============================================================================
docker_compose_header_standards.md - Docker Compose file formatting standards
==============================================================================
Description: Standardized header format for all docker-compose.yml files
Author: Matt Barham
Created: 2025-10-31
Modified: 2026-03-14
Version: 1.3.0
==============================================================================
Document Type: Reference
Audience: Developer
Status: Final
==============================================================================
-->

## Overview

This document defines the standardized header format for all `docker-compose.yml` files in the Spoke infrastructure. Consistent headers improve readability, maintainability, and provide essential metadata at a glance.

Applies to both:
- **Hub**: `hub/docker-compose.yml`
- **Modules**: `modules/{name}/docker-compose.yml`

## Standard Header Template

```yaml
# ==============================================================================
# {HUB|MODULE_NAME} - DOCKER COMPOSE
# ==============================================================================
# Description: {Brief description of purpose}
# Author: Matt Barham
# Created: YYYY-MM-DD
# Modified: YYYY-MM-DD
# Version: X.Y.Z
# Host: Your Server
# ==============================================================================
# Component: {hub | module: name}
# Config Sources: {see below}
# Security: non-root (UID:1000/GID:968), secrets via /run/secrets/, caps dropped
# ==============================================================================
# Container Images:
#   See {env source} for complete image paths and versions
#   ({IMAGE_VAR_1}, {IMAGE_VAR_2}, ...)
# Documentation:
#   - {Service}: {URL}
# Networks:
#   - {network} ({CIDR}) - {description}
# Dependencies:
#   - {Dependency description}
# External Integrations:
#   - [x] {Integration name} ({purpose})
#   - [ ] {Integration name} ({purpose})
# ==============================================================================
```

## Config Sources by Component Type

**Hub** (`hub/docker-compose.yml`):
```yaml
# Config Sources: shared/env/base.env + shared/env/hub.env → hub/.env (generated)
```

**Module** (`modules/{name}/docker-compose.yml`):
```yaml
# Config Sources: base.env + .env.example + modules.yml overrides → .env (generated)
```

## Header Sections Explained

### Section 1: Title and Metadata

```yaml
# ==============================================================================
# {HUB|MODULE_NAME} - DOCKER COMPOSE
# ==============================================================================
# Description: {Brief description of purpose}
# Author: Matt Barham
# Created: YYYY-MM-DD
# Modified: YYYY-MM-DD
# Version: X.Y.Z
# Host: Your Server
# ==============================================================================
```

**Fields:**
- **Title**: Uppercase component name
  - Hub: `HUB - DOCKER COMPOSE`
  - Module: `MONITORING MODULE - DOCKER COMPOSE`
- **Description**: One-line summary of the component's purpose
- **Author**: Always `Matt Barham` for Spoke infrastructure
- **Created**: Initial creation date in YYYY-MM-DD format
- **Modified**: Last modification date in YYYY-MM-DD format
- **Version**: Semantic versioning (MAJOR.MINOR.PATCH)
- **Host**: Always `Your Server`

### Section 2: Configuration Details

```yaml
# Component: hub
# Config Sources: shared/env/base.env + shared/env/hub.env → hub/.env (generated)
# Security: non-root (UID:1000/GID:968), secrets via /run/secrets/, caps dropped
```

**Fields:**
- **Component**: `hub` or `module: {name}`
- **Config Sources**: Environment file merge chain (see above)
- **Security**: Standard security configuration for all containers

### Section 3: Container and Documentation Details

```yaml
# Container Images:
#   See shared/env/hub.env for complete image paths and versions
#   (TRAEFIK_IMAGE, AUTHENTIK_IMAGE, CROWDSEC_IMAGE, POSTGRES_HUB_IMAGE, REDIS_IMAGE)
# Documentation:
#   - Traefik: https://doc.traefik.io/traefik/
```

**Fields:**
- **Container Images**: Reference to env file as single source of truth
  - List environment variable names in parentheses
  - **Pattern**: `{SERVICE}_TAG=1.2.3` and `{SERVICE}_IMAGE=repo/name:${SERVICE_TAG}`
  - Versions are only updated in the env file (single source of truth)
  - NEVER use `latest` tags
- **Documentation**: Official documentation URLs for each service

### Section 4: Infrastructure Details

```yaml
# Networks:
#   - troxy (192.168.35.0/24) - main application network
#   - soxy (192.168.33.0/24) - socket proxy isolated network
# Dependencies:
#   - Hub: socket-proxy, postgres-hub, redis
# External Integrations:
#   - [x] Traefik routing (central reverse proxy)
#   - [x] Authentik forward auth
```

**Fields:**
- **Networks**: Docker networks used with CIDR and purpose
- **Dependencies**: Hub services or other dependencies
- **External Integrations**: Checklist — `[x]` enabled, `[ ]` disabled

## Examples

### Hub Example

```yaml
# ==============================================================================
# HUB - DOCKER COMPOSE
# ==============================================================================
# Description: Core hub infrastructure - socket proxy, reverse proxy, auth, security, DB, cache
# Author: Matt Barham
# Created: 2026-02-12
# Modified: 2026-03-14
# Version: 2.0.0
# Host: Your Server
# ==============================================================================
# Component: hub
# Config Sources: shared/env/base.env + shared/env/hub.env → hub/.env (generated)
# Security: non-root (UID:1000/GID:968), secrets via /run/secrets/, caps dropped
# ==============================================================================
# Container Images:
#   See shared/env/hub.env for complete image paths and versions
#   (SOCKET_PROXY_IMAGE, TRAEFIK_IMAGE, AUTHENTIK_IMAGE, CROWDSEC_IMAGE,
#    POSTGRES_HUB_IMAGE, REDIS_IMAGE)
# Documentation:
#   - Socket Proxy: https://github.com/Tecnativa/docker-socket-proxy
#   - Traefik: https://doc.traefik.io/traefik/
#   - Authentik: https://docs.goauthentik.io/
#   - CrowdSec: https://docs.crowdsec.net/
#   - PostgreSQL: https://hub.docker.com/_/postgres
#   - Redis: https://hub.docker.com/_/redis
# Networks:
#   - soxy (192.168.33.0/24) - socket proxy isolated network
#   - troxy (192.168.35.0/24) - main application network
#   - auxy (192.168.38.0/24) - Authentik auxiliary network
# Dependencies:
#   - None (core hub infrastructure)
# External Integrations:
#   - [x] Cloudflare origin certificates (TLS via /etc/ssl)
#   - [x] CrowdSec bouncer middleware (Traefik plugin)
# ==============================================================================
```

### Module Example

```yaml
# ==============================================================================
# MONITORING MODULE - DOCKER COMPOSE
# ==============================================================================
# Description: Observability stack - metrics, logs, dashboards, alerting
# Author: Matt Barham
# Created: 2026-02-14
# Modified: 2026-03-14
# Version: 1.2.0
# Host: Your Server
# ==============================================================================
# Component: module: monitoring
# Config Sources: base.env + .env.example + modules.yml overrides → .env (generated)
# Security: non-root (UID:1000/GID:968), secrets via /run/secrets/, caps dropped
# ==============================================================================
# Container Images:
#   See modules/monitoring/.env.example for complete image paths and versions
#   (GRAFANA_IMAGE, PROMETHEUS_IMAGE, LOKI_IMAGE, ALLOY_IMAGE, DOZZLE_IMAGE)
# Documentation:
#   - Grafana: https://grafana.com/docs/grafana/latest/
#   - Prometheus: https://prometheus.io/docs/
#   - Loki: https://grafana.com/docs/loki/latest/
# Networks:
#   - troxy (192.168.35.0/24) - main application network
# Dependencies:
#   - Hub: traefik (routing), authentik (forward auth)
# External Integrations:
#   - [x] Traefik routing
#   - [x] Authentik forward auth
#   - [ ] External alertmanager (not configured)
# ==============================================================================
```

## Versioning Guidelines

Use semantic versioning for docker-compose files:

- **MAJOR**: Breaking changes, major service additions/removals, network changes
- **MINOR**: New services, significant configuration changes
- **PATCH**: Bug fixes, version bumps, minor configuration adjustments

## Maintenance Guidelines

1. **Update Modified Date**: Change whenever making changes
2. **Update Version**: Increment according to semantic versioning
3. **Update Container Versions list**: Keep variable names current
4. **Keep Documentation Current**: Verify URLs are still valid
5. **Review Dependencies**: Ensure hub service dependencies are accurate

## Related Files

- `CLAUDE.md` - Main project instructions and standards
- `docs/header_template_reference.md` - General file header standards
- `docs/docker_compose_structure_standards.md` - Complete compose structure

---

**Document Version**: 1.3.0
**Last Updated**: 2026-03-14
**Author**: Matt Barham
**Host**: Your Server
