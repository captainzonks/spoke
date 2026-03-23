# Environment File Header Standards

<!--
==============================================================================
env_file_header_standards.md - Environment file formatting standards
==============================================================================
Description: Standardized header format for all .env files
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

This document defines the standardized header format for all `.env` files in the Spoke infrastructure. Consistent headers across environment files improve security awareness, maintainability, and provide essential metadata for configuration management.

Applies to:
- **Hub env files**: `shared/env/hub.env` and `shared/env/base.env`
- **Module env templates**: `modules/{name}/.env.example`
- **Generated env files**: `hub/.env`, `modules/{name}/.env` (gitignored, auto-generated)
- **Example templates**: `base.env.example`, `hub.env.example`

## Standard Header Template

### Hub / Module Environment Files

```bash
# ==============================================================================
# {HUB|MODULE_NAME} ENVIRONMENT VARIABLES
# ==============================================================================
# Description: {Brief description of purpose}
# Author: Matt Barham
# Created: YYYY-MM-DD
# Modified: YYYY-MM-DD
# Version: X.Y.Z
# Host: Your Server
# ==============================================================================
# Security Level: {HIGH|MEDIUM|LOW} - {security context}
# Component: {hub | module: name}
# ==============================================================================
```

### Base / Global Environment Files

```bash
# ==============================================================================
# {FILE_TITLE}
# ==============================================================================
# Description: {Brief description}
# Author: Matt Barham
# Created: YYYY-MM-DD
# Modified: YYYY-MM-DD
# Version: X.Y.Z
# Host: Your Server
# ==============================================================================
# Security Level: {HIGH|MEDIUM|LOW} - {security context}
# Scope: {Global | Hub + all modules | Utility}
# ==============================================================================
```

### Template Files (`.env.example`)

```bash
# ==============================================================================
# {TEMPLATE_NAME}
# ==============================================================================
# Description: {Brief description of template purpose}
# Author: Matt Barham
# Created: YYYY-MM-DD
# Modified: YYYY-MM-DD
# Version: X.Y.Z
# Host: Your Server
# ==============================================================================
# Type: Template
# Security Level: {HIGH|MEDIUM|LOW} - {security context}
# ==============================================================================
```

## Header Sections Explained

### Section 1: Title and Metadata

```bash
# ==============================================================================
# {HUB|MODULE_NAME} ENVIRONMENT VARIABLES
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
- **Title**: Descriptive title for the environment file
  - Hub files: `HUB ENVIRONMENT VARIABLES`
  - Module files: `MONITORING MODULE ENVIRONMENT VARIABLES`
  - Base files: `BASE ENVIRONMENT VARIABLES - ROME SERVER`
- **Description**: One-line summary of the file's purpose and contents
- **Author**: Always `Matt Barham` for Spoke infrastructure
- **Created**: Initial creation date in YYYY-MM-DD format
- **Modified**: Last modification date in YYYY-MM-DD format
- **Version**: Semantic versioning (MAJOR.MINOR.PATCH)
- **Host**: Always `Your Server`

### Section 2: Security and Scope

```bash
# Security Level: {HIGH|MEDIUM|LOW} - {security context}
# Component: hub
```

**Fields:**
- **Security Level**: Classification of security sensitivity
  - `HIGH`: Contains secrets, passwords, API keys, or sensitive configuration
  - `MEDIUM`: Contains internal network configuration, service endpoints
  - `LOW`: Contains only public version numbers or non-sensitive data
  - Include brief context after the hyphen explaining why
- **Component**: `hub` or `module: {name}`
- **Scope**: For base/global files, describe the reach (e.g., `Global`, `Hub + all modules`)
- **Type**: For template files, specify `Template`

## Security Level Guidelines

### HIGH Security

Files containing:
- Database passwords or credentials
- API keys and secrets
- Authentication tokens
- Encryption keys
- Sensitive application configuration
- Email credentials
- Certificate passwords

**Examples:**
```bash
# Security Level: HIGH - Contains database and authentication configurations
# Security Level: HIGH - Contains secrets and sensitive settings
```

### MEDIUM Security

Files containing:
- Internal IP addresses
- Network configuration
- Service endpoints (internal)
- Non-sensitive application settings
- Resource allocation settings

**Examples:**
```bash
# Security Level: MEDIUM - Contains internal network configuration
# Security Level: MEDIUM - Contains service endpoints
```

### LOW Security

Files containing:
- Public Docker image versions
- Timezone settings
- Public port numbers
- Non-sensitive defaults

**Examples:**
```bash
# Security Level: LOW - Public image versions only
# Security Level: LOW - Non-sensitive configuration defaults
```

## File Organization Standards

### Variable Grouping

Group related variables with section headers:

```bash
#==========================================================================
# {SECTION_NAME}
#==========================================================================

# === Subsection Name (Optional) ===
VARIABLE_NAME=value
ANOTHER_VARIABLE=value
```

**Section header rules:**
- Use 74 `=` characters (matches main header width)
- All caps for section names
- Blank line before section headers
- Optional subsections with `# === Name ===` format

### Variable Naming Conventions

1. **All uppercase**: `VARIABLE_NAME=value`
2. **Underscores for spaces**: `POSTGRES_PASSWORD_FILE`
3. **Service prefix**: `TRAEFIK_IP`, `AUTHENTIK_PORT`
4. **Descriptive names**: Avoid abbreviations unless common

### Variable Format

Always use `VAR=value` (no quotes unless value contains spaces/special chars):

```bash
# Correct
TZ=America/Denver
SPOKE_DIR=/path/to/spoke
TRAEFIK_IMAGE=traefik:3.3.3

# Wrong
TZ="America/Denver"   # No quotes for simple values
DOMAIN="${DOMAIN}"    # No self-referencing
```

### Commenting

```bash
# Single line comment for the next variable
VARIABLE_NAME=value

# === Multi-line Explanation ===
# This variable configures the database connection pool size.
# Higher values improve concurrent connections but use more memory.
# Default: 20, Recommended: 50 for production
DB_POOL_SIZE=50

# Reference to other configuration
# See base.env for CA certificate configuration
SSL_ENABLED=true
```

## Examples

### Hub Environment Example (`shared/env/hub.env`)

```bash
# ==============================================================================
# HUB ENVIRONMENT VARIABLES
# ==============================================================================
# Description: Hub service versions, IPs, and configuration
# Author: Matt Barham
# Created: 2026-02-12
# Modified: 2026-03-14
# Version: 2.1.0
# Host: Your Server
# ==============================================================================
# Security Level: HIGH - Contains authentication configurations
# Component: hub
# ==============================================================================

#==========================================================================
# HUB IMAGE VERSIONS
#==========================================================================
# Two patterns supported:
#   1. TAG+IMAGE: For custom builds or frequently updated images
#      {SERVICE}_TAG=1.2.3 then {SERVICE}_IMAGE=repo:${SERVICE_TAG}
#   2. IMAGE only: For stable third-party images
#      {SERVICE}_IMAGE=repo:1.2.3

# Custom builds (use TAG pattern for easier updates)
TRAEFIK_TAG=3.3.3-custom
TRAEFIK_IMAGE=${SPOKE_DIR}/dockerfiles/traefik:${TRAEFIK_TAG}

# Stable third-party images
REDIS_IMAGE=redis:8.0.1-alpine
SOCKET_PROXY_IMAGE=wollomatic/socket-proxy:1.11.0

#==========================================================================
# HUB NETWORK CONFIGURATION
#==========================================================================
SOCKET_PROXY_IP_S=192.168.33.1
TRAEFIK_IP_S=192.168.33.2
TRAEFIK_IP_T=192.168.35.2
```

### Base Configuration Example (`shared/env/base.env`)

```bash
# ==============================================================================
# BASE ENVIRONMENT VARIABLES - ROME SERVER
# ==============================================================================
# Description: System-wide configuration shared across hub and all modules
# Author: Matt Barham
# Created: 2025-07-10
# Modified: 2026-03-14
# Version: 3.0.0
# Host: Your Server
# ==============================================================================
# Security Level: HIGH - Contains domain, paths, and base secrets
# Scope: Global - Hub and all modules
# ==============================================================================

#==========================================================================
# SYSTEM CONFIGURATION
#==========================================================================

# === Host System Configuration ===
SPOKE_DIR=/path/to/spoke
TZ=America/Denver
HOSTNAME=your-hostname
```

### Module Template Example (`modules/monitoring/.env.example`)

```bash
# ==============================================================================
# MONITORING MODULE ENVIRONMENT VARIABLES
# ==============================================================================
# Description: Observability stack - Grafana, Prometheus, Loki, Alloy, Dozzle
# Author: Matt Barham
# Created: 2026-02-14
# Modified: 2026-03-14
# Version: 1.2.0
# Host: Your Server
# ==============================================================================
# Type: Template
# Security Level: MEDIUM - Contains service endpoints and config
# Component: module: monitoring
# ==============================================================================
```

## Versioning Guidelines

Use semantic versioning for environment files:

- **MAJOR**: Breaking changes, variable removals, major refactoring
- **MINOR**: New variables added, non-breaking configuration changes
- **PATCH**: Value updates, comment improvements, minor fixes

## Security Best Practices

### Secret Handling

1. **Never commit actual secrets**: Use placeholder values or file references
2. **Document secret sources**: Note where actual secrets are stored
3. **Use file references**: Prefer `_FILE` variables pointing to `/run/secrets/`
4. **Security level awareness**: Always mark files with secrets as `HIGH`

### File Permissions

Environment files should have restricted permissions:

```bash
# Recommended permissions for .env files
chmod 600 *.env  # Owner read/write only
```

### Secret References

```bash
# ✅ Good - File reference (secret read at container runtime)
POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password

# ❌ Bad - Plain text secret
# POSTGRES_PASSWORD=supersecret123
```

## Maintenance Guidelines

1. **Update Modified Date**: Change whenever making edits
2. **Update Version**: Follow semantic versioning rules
3. **Review Security Level**: Re-evaluate if adding sensitive variables
4. **Document Changes**: Add comments for non-obvious configurations
5. **Clean Up**: Remove deprecated variables, update comments

## Related Documents

- `docs/docker_compose_header_standards.md` - Compose file header standards
- `docs/header_template_reference.md` - General file header standards
- `docs/secrets_support.md` - Docker secrets support reference
- `CLAUDE.md` - Main project instructions

---

**Document Version**: 1.3.0
**Last Updated**: 2026-03-14
**Author**: Matt Barham
**Host**: Your Server
