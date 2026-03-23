# Docker Compose Structure Standards

<!--
==============================================================================
docker_compose_structure_standards.md - Complete docker-compose.yml structure
==============================================================================
Description: Standardized structure and formatting for docker-compose.yml files
Author: Matt Barham
Created: 2026-02-08
Modified: 2026-03-14
Version: 1.1.0
==============================================================================
Document Type: Reference
Audience: Developer, AI Assistant
Status: Final
==============================================================================
-->

## Overview

This document defines the complete standardized structure for all `docker-compose.yml` files in the Spoke infrastructure. It covers section ordering, formatting conventions, comment styles, and field ordering within services.

Applies to both:
- **Hub** compose file: `hub/docker-compose.yml`
- **Module** compose files: `modules/{name}/docker-compose.yml`

## File Structure Order

All docker-compose.yml files MUST follow this exact section order:

```yaml
1. Header (per docker_compose_header_standards.md)
2. name: declaration
3. EXTENSIONS section
4. NETWORKS section
5. VOLUMES section (if needed)
6. SECRETS section
7. SERVICES section
8. NOTES section (optional, at end of file)
```

## Section Formatting Standards

### 1. Section Separators

Use `#` symbols for section dividers (NOT `=`):

```yaml
############################ EXTENSIONS

############################ NETWORKS

############################# SECRETS

############################# SERVICES
```

**Character counts**:
- Standard sections: 28 `#` characters + 1 space + section name
- Secrets/Services: 29 `#` characters + 1 space + section name

### 2. Extension Definitions

```yaml
############################ EXTENSIONS
x-ssl: &ssl
  environment:
    - SSL_CERT_FILE=${SSL_CERT_FILE}
    - REQUESTS_CA_BUNDLE=${REQUESTS_CA_BUNDLE}
    - CURL_CA_BUNDLE=${CURL_CA_BUNDLE}

  volumes:
    - ${CA_CERT}:/etc/ssl/certs/ca-certificates.crt:ro

x-logging-small: &log_small
  logging:
    driver: json-file
    options:
      max-size: 10m
      max-file: "2"
```

**Standard extensions**:
- `x-ssl: &ssl` - SSL certificate configuration
- `x-logging-important: &log` - Important service logging (50MB max, 3-5 files)
- `x-logging-small: &log_small` - Small service logging (10MB max, 2 files)

### 3. Networks Section

```yaml
############################ NETWORKS
networks:
  # External networks created by hub
  troxy:
    external: true
  soxy:
    external: true

  # Internal networks (if any)
  module_internal:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.x.0.0/24
```

**Guidelines**:
- List external networks first
- List internal networks second
- Include comments describing network purpose
- Use consistent naming: `{module}_internal` for module-specific networks

### 4. Volumes Section

```yaml
############################ VOLUMES
volumes:
  volume_name:
    driver: local
```

**Only include if the compose file defines named volumes**. Skip this section if no volumes are defined.

### 5. Secrets Section

```yaml
############################# SECRETS
secrets:
  secret_name:
    file: ${SPOKE_DIR}/secrets/category/secret_name
```

**Guidelines**:
- Group related secrets together
- Use `${SPOKE_DIR}` (NOT `${DOCKERDIR}` or other legacy names) (for consistency)
- Organize by service or category
- Add comment headers for secret groups if list is long

## Service Definition Standards

### Service Section Header

```yaml
############################# SERVICES
services:
  #======================================
  # SERVICE_NAME - Short Description
  #======================================
  servicename:
```

**Service separator**:
- Use 38 `#` characters: `#======================================`
- Comment format: `# SERVICE_NAME - Short Description`
- Service name in ALL CAPS in comment
- Description is concise (1 line, not multi-line)

### Service Field Order

Services MUST use this exact field order:

```yaml
servicename:
  <<: [*ssl, *log]           # 1. Extensions (if used)
  image:                      # 2. Image
  build:                      # 3. Build (if custom image)
    context:
    dockerfile:
    args:
    x-bake:
  hostname:                   # 4. Hostname
  container_name:             # 5. Container name
  restart:                    # 6. Restart policy
  profiles:                   # 7. Profiles

  security_opt:               # 8. Security options
  read_only:                  # 9. Read-only filesystem (if applicable)
  mem_limit:                  # 10. Memory limit
  cpus:                       # 11. CPU limit
  cap_drop:                   # 12. Dropped capabilities
  cap_add:                    # 13. Added capabilities (if needed)
  user:                       # 14. User/group
  group_add:                  # 15. Additional groups (if needed)

  devices:                    # 16. Device mappings (if needed)

  networks:                   # 17. Networks

  ports:                      # 18. Port mappings
  # OR
  expose:                     # 18. Exposed ports (internal only)

  depends_on:                 # 19. Dependencies (if needed)

  healthcheck:                # 20. Health check

  command:                    # 21. Command override (if needed)

  environment:                # 22. Environment variables

  volumes:                    # 23. Volume mounts

  tmpfs:                      # 24. Tmpfs mounts (if needed)

  secrets:                    # 25. Secrets (last)
```

### Resource Limits Format

Use either the compact format OR the deploy format (be consistent per compose file):

**Compact format** (preferred for simple limits):
```yaml
mem_limit: 2G
cpus: 2.0
```

**Deploy format** (for complex resource management):
```yaml
deploy:
  resources:
    limits:
      memory: 2G
      cpus: '2.0'
    reservations:
      memory: 1G
      cpus: '1.0'
```

### Network Assignment Formats

**Single network** (no IP):
```yaml
networks:
  troxy:
```

**Single network** (with static IP):
```yaml
networks:
  troxy:
    ipv4_address: ${SERVICE_IP}
```

**Multiple networks** (mixed):
```yaml
networks:
  soxy:
    ipv4_address: ${SERVICE_IP_S}
  troxy:
    ipv4_address: ${SERVICE_IP_T}
```

**Multiple networks** (list format without IPs):
```yaml
networks:
  - genetics_isolated
  - genetics_db_network
  - troxy
```

**Note**: Use the key format (`network:`) when assigning static IPs. Use list format (`- network`) only for dynamic IP assignment on multiple networks.

### Environment Variables

**Format**:
```yaml
environment:
  - TZ=${TZ}
  - DOMAIN=${DOMAIN}
  - POSTGRES_USER=${POSTGRES_USER}
```

**Guidelines**:
- ALWAYS use `VAR=${VAR}` format (never bare variables, never quoted)
- Group related variables together
- Common variables first (TZ, DOMAIN, HOSTNAME)
- Service-specific variables after
- Secret file paths last
- Add comment sections for variable groups if list is long

### Volume Mounts

```yaml
volumes:
  - ${SPOKE_DIR}/appdata/service/config/:/config/:rw
  - ${DATA_DIR}/data/:/data/:ro
  - ${LOCALTIME}:/etc/localtime:ro
```

**Guidelines**:
- Config/data mounts first
- Read-only system mounts last (like /etc/localtime)
- Always specify `:ro` or `:rw` explicitly
- Use `${SPOKE_DIR}` for appdata paths (NOT `${ROME_DIR}` or `${DOCKERDIR}`)
- Use appropriate data directory variables

### Tmpfs Mounts

```yaml
tmpfs:
  - /tmp/:rw,size=200m
  - /run/:rw,size=100m # daemon state
  - /dev/shm/:rw,size=512m # specific purpose comment
```

**Guidelines**:
- Include size limits
- Add inline comments describing purpose for non-obvious mounts
- Common purposes: cache, daemon state, rendering, transcoding

## Best Practices

### Comments

1. **Section comments**: Use for major sections only
2. **Service comments**: ONE line describing the service
3. **Inline comments**: Clarify non-obvious configurations
4. **Avoid**: Don't duplicate information obvious from the field name

### Consistency

1. **Use same separator style** across all files (`####` not `===`)
2. **Maintain field order** exactly as specified
3. **Group related items** (env vars, volumes, secrets)
4. **Use consistent naming** for variables and services

### Security

1. **Never hardcode secrets** in environment variables
2. **Always use** `no-new-privileges=true`
3. **Drop all capabilities** by default (`cap_drop: ALL`)
4. **Only add capabilities** when absolutely required
5. **Run as non-root** when supported (`user: 1000:968`)

## Related Documents

- `docs/docker_compose_header_standards.md` - Header format standards
- `docs/env_file_header_standards.md` - Environment file standards
- `docs/secrets_support.md` - Docker secrets support reference
- `CLAUDE.md` - Main project instructions

---

**Document Version**: 1.1.0
**Last Updated**: 2026-03-14
**Author**: Matt Barham
**Host**: Your Server
