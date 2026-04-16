# Docker Secrets Support Reference

<!--
==============================================================================
secrets_support.md - Docker Secrets Implementation Guide
==============================================================================
Description: Comprehensive reference for Docker secrets support across all
             services deployed with Spoke server. Documents native support,
             custom implementations, and workarounds for each service type.
Author: Matt Barham
Created: 2025-07-26
Modified: 2026-02-18
Version: 3.1.0
==============================================================================
Document Type: Reference
Audience: System Administrator
Status: Active
==============================================================================
-->

## Overview

This document tracks Docker secrets support capabilities for all services deployed with Spoke. Docker secrets allow sensitive data to be mounted as files in `/run/secrets/` rather than exposed as environment variables, improving security.

**Key Concepts:**
- **Native Support**: Image natively reads from file paths using `_FILE` suffix or similar patterns
- **Custom Implementation**: Spoke's custom Dockerfiles add secrets support via entrypoint scripts
- **Config File Expansion**: Service reads secrets via config file variable expansion
- **No Support**: Requires workarounds (init containers, external scripts, or hardcoded values)

## Quick Reference Table

| Service | Support Type | Variable Format | Notes |
|---------|--------------|-----------------|-------|
| PostgreSQL | Native | `VAR_FILE` | Official image standard |
| Traefik | Custom | `VAR_FILE` | Spoke custom entrypoint |
| Authentik | Native | `file:///path` | Unique URI format |
| MinIO | Native | `VAR_FILE` | Standard suffix |
| Grafana | Native | `GF_VAR__FILE` | Double underscore |
| Vault | Config | N/A | HCL config file |
| Prometheus | Custom | `VAR_FILE` | Spoke custom entrypoint |
| Loki | Config | `${VAR}` | Config expansion |
| Telegraf | Plugin | `@{secretstore:key}` | Secret store plugin |
| Dozzle | Native | `VAR_FILE` | Standard suffix |
| Plex (LSIO) | Native | `FILE__VAR` | Prefix pattern |
| Homepage | Native | `HOMEPAGE_FILE_VAR` | Custom prefix |
| Gluetun | Native | `FILE__VAR` | Prefix pattern |
| FoundryVTT | Config | JSON secrets file | Alternative approach |
| InfluxDB3 | None | N/A | Direct env only |
| Redis | None | N/A | No env support |
| CouchDB | None | N/A | PR pending |
| VictoriaMetrics | Config | `${VAR}` | Config expansion |
| socket-proxy | None | N/A | Direct env only |
| CrowdSec | Custom | `VAR_FILE` | Spoke custom build |
| Navidrome | None | N/A | Feature requested |
| qBittorrent | None | N/A | Use LSIO alternative |
| Tautulli | Unknown | N/A | Not documented |
| Picard | None | N/A | GUI application |
| Stash | Unknown | N/A | Not documented |
| Protonmail Bridge | Custom | `VAR_FILE` | Spoke custom build |
| qSticky | N/A | N/A | No secrets needed |
| Slskd | Native | Config YAML | Secrets in config file |
| Immich | Native | Env vars | Uses standard patterns |
| Genetics Stack | Custom | `VAR_FILE` | Spoke custom builds |
| Daggerheart MCP | N/A | N/A | No secrets needed |
| Portfolio Stack | N/A | N/A | Static site, no secrets |

## Detailed Service Documentation

### Infrastructure & Networking

#### Traefik
**Support**: Custom (Spoke Implementation)
**Format**: `VAR_FILE=/run/secrets/secret_name`
**Image**: `rome/traefik:3.6.13-custom`

Traefik has basic `_FILE` support for some variables in newer versions, but Spoke's custom entrypoint.sh provides comprehensive handling for all secret variables.

**Implementation**:
```yaml
environment:
  - CF_DNS_API_TOKEN_FILE=/run/secrets/cloudflare_api_token
secrets:
  cloudflare_api_token:
    file: ${SPOKE_DIR}/secrets/traefik/cloudflare_api_token
```

**Documentation**:
- https://doc.traefik.io/traefik/providers/docker/#docker-api-access
- Custom: `dockerfiles/traefik/entrypoint.sh`

---

#### Authentik
**Support**: Native
**Format**: `AUTHENTIK_VAR=file:///run/secrets/secret_name`
**Image**: `ghcr.io/goauthentik/server:2025.12.1`

Authentik uses a unique URI-based format for file references. Must use triple slash `file:///` prefix.

**Implementation**:
```yaml
environment:
  - AUTHENTIK_SECRET_KEY=file:///run/secrets/authentik_secret_key
  - AUTHENTIK_POSTGRESQL__PASSWORD=file:///run/secrets/postgres_password
secrets:
  authentik_secret_key:
    file: ${SPOKE_DIR}/secrets/authentik/authentik_secret_key
  postgres_password:
    file: ${SPOKE_DIR}/secrets/postgres/postgres_password
```

**Documentation**:
- https://docs.goauthentik.io/docs/installation/configuration
- https://github.com/goauthentik/authentik/blob/main/authentik/lib/config.py

**Notes**: Double underscore (`__`) separates nested config keys.

---

#### CrowdSec
**Support**: Custom (Spoke Implementation)
**Format**: `VAR_FILE=/run/secrets/secret_name`
**Image**: `rome/crowdsec:v1.7.7-custom`

Spoke's custom build adds `_FILE` support via entrypoint preprocessing.

**Documentation**:
- https://docs.crowdsec.net/docs/configuration/crowdsec_configuration
- Custom: `dockerfiles/crowdsec/`

---

#### socket-proxy
**Support**: None
**Image**: `wollomatic/socket-proxy:1.11.4`

Lightweight proxy with minimal configuration. No sensitive secrets required (uses socket permissions).

**Documentation**: https://github.com/wollomatic/socket-proxy

---

#### Gluetun
**Support**: Native
**Format**: `FILE__VAR=/path/to/secret`
**Image**: `qmcgaw/gluetun:latest`

Uses prefix pattern with double underscore. File path can be anywhere container can read.

**Implementation**:
```yaml
environment:
  - FILE__OPENVPN_USER=/run/secrets/vpn_username
  - FILE__OPENVPN_PASSWORD=/run/secrets/vpn_password
secrets:
  vpn_username:
    file: ${SPOKE_DIR}/secrets/gluetun/vpn_username
  vpn_password:
    file: ${SPOKE_DIR}/secrets/gluetun/vpn_password
```

**Documentation**:
- https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/environment-variables.md#file-variables

---

### Databases

#### PostgreSQL
**Support**: Native
**Format**: `VAR_FILE=/run/secrets/secret_name`
**Image**: `rome/postgres:18.3-custom` / `rome/postgres:17.7-custom`

Official PostgreSQL images support `_FILE` suffix for all `POSTGRES_*` variables.

**Implementation**:
```yaml
environment:
  - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
  - POSTGRES_USER=${POSTGRES_USER}
  - POSTGRES_DB=${POSTGRES_DB}
secrets:
  postgres_password:
    file: ${SPOKE_DIR}/secrets/postgres/postgres_password
```

**Documentation**:
- https://hub.docker.com/_/postgres (see "Docker Secrets" section)
- https://github.com/docker-library/postgres/blob/master/docker-entrypoint.sh

**Supported Variables**: `POSTGRES_PASSWORD`, `POSTGRES_USER`, `POSTGRES_DB`, `POSTGRES_INITDB_ARGS`

---

#### Redis
**Support**: None
**Image**: `redis:8.6.2-alpine`

Official Redis image doesn't use environment variables for configuration. Uses command-line arguments or redis.conf file.

**Workarounds**:
1. Mount custom redis.conf with secrets substituted by init container
2. Use `--requirepass $(cat /run/secrets/redis_password)` in command (requires shell)
3. Use Redis ACL file mounted from secret

**Documentation**:
- https://hub.docker.com/_/redis
- https://redis.io/docs/management/security/acl/

---

#### InfluxDB v3
**Support**: None
**Format**: Direct environment variables only
**Image**: `rome/influxdb3:3.8.0-core-custom`

InfluxDB 3.x (Core) doesn't support `_FILE` suffix. Uses direct env vars only.

**Workaround**: Add custom entrypoint to Spoke's Dockerfile to handle `_FILE` variables.

**Documentation**:
- https://github.com/influxdata/influxdb/tree/main-3.x
- https://docs.influxdata.com/influxdb/v3/

**Note**: InfluxDB 2.x (different product) has some `_FILE` support.

---

#### CouchDB
**Support**: None (Pending)
**Image**: `couchdb:3.5.1`

Feature requested but not merged. PR #205 adds `_FILE` support but not in official builds.

**Workaround**: Use init container to create local.ini from secrets.

**Documentation**:
- https://github.com/apache/couchdb-docker/pull/205
- https://hub.docker.com/_/couchdb

---

#### VictoriaMetrics
**Support**: Config File Expansion
**Format**: Environment variable expansion in config
**Image**: `victoriametrics/victoria-metrics:v1.132.0`

Supports `${VAR}` expansion in config files. Mount secret, export as env var, reference in config.

**Implementation**:
```yaml
environment:
  - VM_PASSWORD=$(cat /run/secrets/vm_password)
# Or use config file with: password: ${VM_PASSWORD}
```

**Documentation**:
- https://docs.victoriametrics.com/single-server-victoriametrics/#environment-variables

---

### Storage & Secrets Management

#### MinIO
**Support**: Native
**Format**: `VAR_FILE=/run/secrets/secret_name`
**Image**: `minio/minio:RELEASE.2025-09-07T16-13-09Z`

Comprehensive `_FILE` support for all MINIO_* environment variables.

**Implementation**:
```yaml
environment:
  - MINIO_ROOT_USER_FILE=/run/secrets/minio_root_user
  - MINIO_ROOT_PASSWORD_FILE=/run/secrets/minio_root_password
secrets:
  minio_root_user:
    file: ${SPOKE_DIR}/secrets/minio/minio_root_user
  minio_root_password:
    file: ${SPOKE_DIR}/secrets/minio/minio_root_password
```

**Documentation**:
- https://min.io/docs/minio/linux/reference/minio-server/minio-server.html#envvar-MINIO_ROOT_USER_FILE
- https://github.com/minio/minio/blob/master/docs/docker/README.md#secrets-support

---

#### HashiCorp Vault
**Support**: HCL Config File
**Format**: Configuration via HCL/JSON
**Image**: `hashicorp/vault:1.20.3`

Vault is a secrets manager itself. Configuration via HCL file with secrets referenced from files.

**Implementation**:
```hcl
# vault.hcl
seal "awskms" {
  kms_key_id = "file:///run/secrets/kms_key_id"
}
```

**Documentation**:
- https://developer.hashicorp.com/vault/docs/configuration
- https://developer.hashicorp.com/vault/tutorials/docker

---

### Monitoring & Observability

#### Grafana
**Support**: Native
**Format**: `GF_VAR__FILE=/run/secrets/secret_name` (double underscore)
**Image**: `grafana/grafana:12.4.0-21342258703`

Uses unique double underscore pattern: `GF_SECTION_KEY__FILE`

**Implementation**:
```yaml
environment:
  - GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana_admin_password
  - GF_DATABASE_PASSWORD__FILE=/run/secrets/grafana_db_password
secrets:
  grafana_admin_password:
    file: ${SPOKE_DIR}/secrets/grafana/admin_password
  grafana_db_password:
    file: ${SPOKE_DIR}/secrets/postgres/grafana_password
```

**Documentation**:
- https://grafana.com/docs/grafana/latest/setup-grafana/configure-docker/#use-docker-secrets
- https://github.com/grafana/grafana/blob/main/pkg/setting/setting.go

**Pattern**: `GF_<SECTION>_<KEY>__FILE` (note double underscore before FILE)

---

#### Prometheus
**Support**: Custom (Spoke Implementation)
**Format**: `VAR_FILE=/run/secrets/secret_name`
**Image**: `rome/prometheus:v3.9.1-custom`

Prometheus has limited env var support. Spoke's custom build adds entrypoint for `_FILE` handling.

**Documentation**:
- https://prometheus.io/docs/prometheus/latest/configuration/configuration/
- Custom: `dockerfiles/prometheus/`

**Note**: Prometheus config uses `${VAR}` expansion, so entrypoint exports secrets as env vars.

---

#### Loki
**Support**: Config File Expansion
**Format**: `${VAR}` in YAML config
**Image**: `grafana/loki:3.6.4`

Loki supports environment variable expansion in config files. Mount secret, export as env var.

**Implementation**:
```yaml
# loki-config.yml
auth:
  type: basic
  basic_auth:
    password: ${LOKI_PASSWORD}
```

**Documentation**:
- https://grafana.com/docs/loki/latest/configure/#use-environment-variables-in-the-configuration
- https://grafana.com/docs/loki/latest/operations/authentication/

---

#### Telegraf
**Support**: Secret Store Plugin
**Format**: `@{secretstore:key}` in config
**Image**: `rome/telegraf:1.37.1-custom`

Telegraf has a secret store plugin system. Requires additional configuration.

**Implementation**:
```toml
# telegraf.conf
[[secretstores.file]]
  directory = "/run/secrets"

[[inputs.postgresql]]
  password = "@{secretstore:postgres_password}"
```

**Documentation**:
- https://docs.influxdata.com/telegraf/latest/configuration/#secretstores
- https://github.com/influxdata/telegraf/tree/master/plugins/secretstores

**Note**: Spoke's custom build may include simpler `_FILE` preprocessing.

---

#### Dozzle
**Support**: Native
**Format**: `VAR_FILE=/run/secrets/secret_name`
**Image**: `amir20/dozzle:v9.0.3`

Supports `_FILE` suffix for authentication variables.

**Implementation**:
```yaml
environment:
  - DOZZLE_USERNAME_FILE=/run/secrets/dozzle_username
  - DOZZLE_PASSWORD_FILE=/run/secrets/dozzle_password
```

**Documentation**:
- https://dozzle.dev/guide/authentication#using-docker-secrets
- https://github.com/amir20/dozzle

---

#### Grafana Alloy
**Support**: Config File
**Format**: HCL config with file() function
**Image**: `grafana/alloy:v1.12.2`

Alloy (successor to Grafana Agent) uses River config language with file reading functions.

**Implementation**:
```river
// config.alloy
loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
    basic_auth {
      username = "loki"
      password = file("/run/secrets/loki_password")
    }
  }
}
```

**Documentation**:
- https://grafana.com/docs/alloy/latest/configure/
- https://grafana.com/docs/alloy/latest/reference/stdlib/file/

---

### Media Services

#### Plex (LinuxServer.io)
**Support**: Native
**Format**: `FILE__VAR=/path/to/secret` (prefix pattern)
**Image**: `lscr.io/linuxserver/plex:1.42.2`

LinuxServer.io images use prefix pattern with double underscore.

**Implementation**:
```yaml
environment:
  - FILE__PLEX_CLAIM=/run/secrets/plex_claim
secrets:
  plex_claim:
    file: ${SPOKE_DIR}/secrets/plex/claim_token
```

**Documentation**:
- https://docs.linuxserver.io/general/docker-secrets
- https://github.com/linuxserver/docker-plex

**Pattern**: Works for all LinuxServer.io images (Plex, Tautulli may support this)

---

#### Navidrome
**Support**: None
**Image**: `deluan/navidrome:0.59.0`

Feature requested in Discussion #3463 but not implemented.

**Workaround**: Use init container to generate config file from secrets.

**Documentation**:
- https://github.com/navidrome/navidrome/discussions/3463
- https://www.navidrome.org/docs/usage/configuration-options/

---

#### qBittorrent (hotio)
**Support**: None
**Image**: `ghcr.io/hotio/qbittorrent:release-5.1.2`

Hotio image doesn't document secrets support.

**Alternative**: LinuxServer.io qBittorrent image supports `FILE__` pattern.

**Documentation**:
- https://hotio.dev/containers/qbittorrent/
- Alternative: https://docs.linuxserver.io/images/docker-qbittorrent

---

#### Tautulli
**Support**: Possible (LinuxServer.io pattern)
**Format**: `FILE__VAR` if supported
**Image**: `ghcr.io/tautulli/tautulli:v2.16.0`

Official Tautulli image, not LinuxServer.io. May not support `FILE__` pattern.

**Documentation**:
- https://github.com/Tautulli/Tautulli-Docker
- https://github.com/Tautulli/Tautulli/wiki/Installation-Guides

---

#### MusicBrainz Picard
**Support**: None
**Image**: `mikenye/picard:2.13.3`

GUI application, typically configured interactively. No secrets in environment.

**Documentation**: https://github.com/mikenye/docker-picard

---

#### Stash
**Support**: Unknown
**Image**: `rome/stash:hwaccel-alpine-2025-12-26-custom`

Spoke custom build. Support depends on custom implementation.

**Documentation**:
- https://github.com/stashapp/stash
- Custom: `dockerfiles/stash/`

---

### Applications

#### Protonmail Bridge
**Support**: Custom (Spoke Implementation)
**Format**: `VAR_FILE=/run/secrets/secret_name`
**Image**: `rome/protonmail-bridge:1.0_v3.21.2-custom`

Spoke's custom build adds secrets support. Official image requires interactive setup.

**Documentation**:
- https://github.com/shenxn/protonmail-bridge-docker
- Custom: `dockerfiles/protonmail-bridge/`

---

#### Homepage
**Support**: Native
**Format**: `HOMEPAGE_FILE_VAR=/path/to/secret`
**Image**: `ghcr.io/gethomepage/homepage:v1.8.0`

Custom prefix pattern for secrets.

**Implementation**:
```yaml
environment:
  - HOMEPAGE_FILE_AUTHENTIK_TOKEN=/run/secrets/homepage_authentik_token
secrets:
  homepage_authentik_token:
    file: ${SPOKE_DIR}/secrets/homepage/authentik_token
```

**Documentation**:
- https://gethomepage.dev/latest/installation/docker/#using-secrets
- https://github.com/gethomepage/homepage

---

#### Slskd (SoulSeek)
**Support**: Native (Config YAML)
**Format**: Secrets in YAML config file
**Image**: `slskd/slskd:0.24.2`

Slskd uses a YAML configuration file where secrets can be placed. Supports environment variable expansion in config.

**Implementation**:
```yaml
# slskd.yml
soulseek:
  username: ${SLSKD_USERNAME}
  password: ${SLSKD_PASSWORD}
```

**Documentation**:
- https://github.com/slskd/slskd
- https://github.com/slskd/slskd/blob/master/docs/config.md

---

#### FoundryVTT
**Support**: JSON Secrets File
**Format**: Custom JSON file approach
**Image**: `felddy/foundryvtt:13.351.0`

Uses a secrets.json file approach rather than individual secret files.

**Implementation**:
```json
{
  "adminKey": "your-admin-password",
  "licenseKey": "your-license-key"
}
```

Mount as: `/data/secrets.json`

**Documentation**:
- https://github.com/felddy/foundryvtt-docker
- https://foundryvtt.com/article/docker/

---

### Photo Management

#### Immich
**Support**: Native
**Format**: Standard environment variables
**Image**: `ghcr.io/immich-app/immich-server:v2.4.1`

Immich uses standard PostgreSQL and Redis connections via environment variables. The Immich stack includes its own PostgreSQL (with pgvector) and Redis instances.

**Implementation**:
```yaml
environment:
  - DB_PASSWORD=${IMMICH_DB_PASSWORD}
  - REDIS_PASSWORD=${IMMICH_REDIS_PASSWORD}
# Immich does not currently support _FILE suffix
```

**Documentation**:
- https://immich.app/docs/install/environment-variables
- https://github.com/immich-app/immich

**Note**: Consider custom entrypoint for `_FILE` support if needed.

---

### Custom Spoke Stacks

#### Genetics Stack (GeneGnome)
**Support**: Custom (Spoke Implementation)
**Format**: `VAR_FILE` via custom entrypoints
**Images**: `rome/genetics-api-gateway:1.0.0`, `rome/genetics-frontend:1.0.0`, `rome/genetics-worker:1.0.0`

Spoke's genetics module uses custom-built containers with `_FILE` support in entrypoints.

**Components**:
- `genetics-api-gateway` - FastAPI backend
- `genetics-frontend` - React frontend
- `genetics-worker` - Background task processor
- `genetics-redis` - Redis for caching/queues
- `postgres18-genetics` - PostgreSQL 18.3 database

**Implementation**:
```yaml
environment:
  - DATABASE_URL_FILE=/run/secrets/genetics_db_url
  - REDIS_URL_FILE=/run/secrets/genetics_redis_url
secrets:
  genetics_db_url:
    file: ${SPOKE_DIR}/secrets/genetics/db_url
```

**Documentation**: Custom Spoke stack - see `stacks/genetics/`

---

#### Daggerheart MCP
**Support**: N/A
**Image**: `daggerheart_mcp:latest`

MCP server for Daggerheart TTRPG rules. No secrets required - serves static game rules data.

**Documentation**: Custom Spoke stack - see `stacks/daggerheart/`

---

#### Portfolio Stack
**Support**: N/A
**Images**: `rome/portfolio-site:0.139.3`, `rome/portfolio-form-handler:1.0.0`

Static Hugo site with form handler. No secrets required in containers (form handler uses external email service).

**Documentation**: Custom Spoke stack - see `stacks/portfolio/`

---

## Implementation Patterns

### Pattern 1: Standard `_FILE` Suffix
```yaml
environment:
  - POSTGRES_PASSWORD_FILE=/run/secrets/db_password
secrets:
  db_password:
    file: ${SPOKE_DIR}/secrets/service/db_password
```

**Services**: PostgreSQL, MinIO, Dozzle, Traefik (custom)

---

### Pattern 2: Prefix with Double Underscore
```yaml
environment:
  - FILE__API_KEY=/run/secrets/api_key
secrets:
  api_key:
    file: ${SPOKE_DIR}/secrets/service/api_key
```

**Services**: Gluetun, Plex/LinuxServer.io images

---

### Pattern 3: URI File Reference
```yaml
environment:
  - AUTHENTIK_SECRET_KEY=file:///run/secrets/secret_key
secrets:
  secret_key:
    file: ${SPOKE_DIR}/secrets/authentik/secret_key
```

**Services**: Authentik only

---

### Pattern 4: Custom Prefix
```yaml
environment:
  - HOMEPAGE_FILE_TOKEN=/run/secrets/token
  - GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/admin_pass
secrets:
  token:
    file: ${SPOKE_DIR}/secrets/service/token
```

**Services**: Homepage (`HOMEPAGE_FILE_`), Grafana (`__FILE`)

---

### Pattern 5: Config File Expansion
```yaml
# config.yml
database:
  password: ${DB_PASSWORD}

# docker-compose.yml
environment:
  - DB_PASSWORD=$(cat /run/secrets/db_password)
# OR mount secret and reference in entrypoint
```

**Services**: Loki, VictoriaMetrics, Vault

---

### Pattern 6: Custom Entrypoint
Add preprocessing to read secrets before main process:

```bash
#!/bin/bash
# entrypoint.sh
for var in $(compgen -e); do
  if [[ $var == *_FILE ]]; then
    file_path="${!var}"
    var_name="${var%_FILE}"
    if [ -f "$file_path" ]; then
      export "$var_name"="$(cat "$file_path")"
    fi
  fi
done
exec "$@"
```

**Services**: Spoke custom builds (Traefik, Prometheus, CrowdSec, Protonmail Bridge)

---

## Spoke Custom Implementations

Spoke has several custom Dockerfile builds that add secrets support where not natively available:

| Service | Custom Feature |
|---------|----------------|
| Traefik | Comprehensive `_FILE` preprocessing |
| Prometheus | `_FILE` support + config templating |
| CrowdSec | `_FILE` support for API keys |
| Protonmail Bridge | `_FILE` support + automated setup |
| InfluxDB3 | (Consider adding) `_FILE` preprocessing |
| Telegraf | Possibly custom `_FILE` support |
| Stash | Unknown custom features |

**Location**: `dockerfiles/{service}/entrypoint.sh`

---

## Best Practices

### When to Use Docker Secrets
✅ **Use for**:
- Passwords, API keys, tokens
- TLS certificates and keys
- OAuth client secrets
- Database credentials
- Service-to-service authentication

❌ **Don't use for**:
- Non-sensitive configuration (use env vars)
- Public information (use config files)
- Data that needs to be updated frequently (secrets require container restart)

### Security Considerations
1. **Never commit secrets to git** - Use `.gitignore` for `secrets/` directory
2. **Restrict file permissions** - `chmod 600` for secret files
3. **Use separate secrets per service** - Don't share passwords
4. **Rotate secrets regularly** - Update and restart containers
5. **Audit secret access** - Track which containers mount which secrets

### Handling Services Without Support
For services without native `_FILE` support:

1. **Custom entrypoint** (preferred): Add preprocessing script
2. **Init container**: Generate config from secrets before main container
3. **External script**: Create config files before `docker compose up`
4. **Config file with expansion**: Mount secret, reference in config with `${VAR}`

**Example init container**:
```yaml
services:
  init:
    image: alpine:latest
    volumes:
      - config:/config
    secrets:
      - db_password
    command: >
      sh -c "echo 'password: '$(cat /run/secrets/db_password) > /config/app.yml"

  app:
    image: myapp:latest
    depends_on:
      init:
        condition: service_completed_successfully
    volumes:
      - config:/config
```

---

## Verification & Testing

### Test Secret Loading
```bash
# Check if secret file exists in container
docker exec <container> ls -la /run/secrets/

# Verify secret content (be careful with sensitive data!)
docker exec <container> cat /run/secrets/<secret_name>

# Check if environment variable is set (for _FILE variables)
docker exec <container> env | grep <VAR>_FILE

# Check if value was loaded (if service exposes this)
docker exec <container> <service-cli> config show
```

### Troubleshooting
**Secret not loading**:
1. Verify file exists on host: `cat ${SPOKE_DIR}/secrets/service/secret_name`
2. Check mount in container: `docker exec <container> ls /run/secrets/`
3. Verify permissions: `ls -la ${SPOKE_DIR}/secrets/service/`
4. Check service logs: `docker logs <container> 2>&1 | grep -i secret`

**Wrong format error**:
1. Verify exact format for service (check table above)
2. Check for typos (double underscore vs single)
3. Verify file path is correct (some use relative paths)

---

## Version-Specific Notes

### PostgreSQL
- **All versions**: Support `_FILE` suffix since ancient times
- Pattern is from official Docker entrypoint script

### Traefik
- **v2.x**: Limited `_FILE` support
- **v3.x**: Expanded support but not comprehensive
- Spoke custom: Works with all versions

### Authentik
- **2024.x**: Introduced `file://` format
- **2025.x**: Current format `file:///` (triple slash)

### Grafana
- **v8.x+**: Added `__FILE` support
- **v10.x+**: Comprehensive secret support

### InfluxDB
- **v2.x**: Some `_FILE` support
- **v3.x**: No `_FILE` support (different codebase)

---

## Future Improvements

**Services that could benefit from custom entrypoints**:
1. **InfluxDB3** - Add `_FILE` support (currently uses direct env vars)
2. **Redis** - Add config generation from secrets
3. **Navidrome** - Add config generation from secrets
4. **qBittorrent** - Switch to LinuxServer.io image OR add custom support

**Documentation improvements**:
- Add example compose snippets for each pattern
- Create testing scripts for secret validation
- Document secret rotation procedures

---

## References

### Official Documentation
- [Docker Secrets Documentation](https://docs.docker.com/engine/swarm/secrets/)
- [Docker Compose Secrets](https://docs.docker.com/compose/use-secrets/)
- [PostgreSQL Docker Secrets](https://hub.docker.com/_/postgres)
- [Traefik Configuration](https://doc.traefik.io/traefik/)
- [Authentik Configuration](https://docs.goauthentik.io/docs/installation/configuration)
- [MinIO Secrets](https://min.io/docs/minio/linux/reference/minio-server/minio-server.html)
- [Grafana Docker Secrets](https://grafana.com/docs/grafana/latest/setup-grafana/configure-docker/)

### Community Resources
- [LinuxServer.io Docker Secrets](https://docs.linuxserver.io/general/docker-secrets)
- [Gluetun File Variables](https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/environment-variables.md)
- [Homepage Secrets](https://gethomepage.dev/latest/installation/docker/#using-secrets)

### Spoke-Specific
- `CLAUDE.md` - Docker secrets management standards
- `dockerfiles/*/entrypoint.sh` - Custom secrets implementations
- `shared/env/*.env` - Service configuration (non-secret values)

---

## Changelog

### Version 3.1.0 (2026-02-18)
- Changed all `${DOCKERDIR}` references to `${SPOKE_DIR}` for consistency with compose files

### Version 3.0.0 (2026-01-20)
- Updated all service versions to current deployed versions
- Changed image prefix from `localhost/` to `rome/` for custom builds
- Added new services: Immich, Genetics Stack, Daggerheart MCP, Portfolio Stack, Slskd
- Added Photo Management and Custom Spoke Stacks sections
- Updated quick reference table with new services

### Version 2.0.0 (2025-11-01)
- Complete rewrite with comprehensive service research
- Added detailed implementation patterns for all Spoke services
- Documented custom implementations in Spoke builds
- Added version-specific notes and troubleshooting
- Organized by service category with quick reference table
- Added official documentation links for each service
- Included security best practices and testing procedures

### Version 1.0.0 (2025-07-26)
- Initial documentation
- Basic list of supported services

---

**Last Updated**: 2026-02-18
**Next Review**: 2026-04-01 (or when new services added)
**Maintained By**: Matt Barham
