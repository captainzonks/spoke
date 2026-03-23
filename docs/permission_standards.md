# Spoke Permission Standards

**Date:** 2025-11-05
**Purpose:** Standardized Unix permissions across Spoke directories
**Owner:** your-user (UID 1000)
**Group:** docker (GID 968)

## Overview

After removing legacy POSIX ACL complexity, Spoke uses consistent standard Unix permissions for security and maintainability. All services run as `user: "1000:968"` in docker-compose.yml where possible.

## Permission Standards

### General Directories (755 - rwxr-xr-x)

**Applies to:**
- Spoke root directory
- docs/
- stacks/
- scripts/
- shared/
- archive/
- backups/
- build/
- dockerfiles/
- logs/
- dev/
- .git/
- .vault_backups/
- .vault_overrides/

**Reasoning:** Standard readable directories for code, documentation, and configuration. Owner and group have full access, others can read and navigate.

### General Files (644 - rw-r--r--)

**Applies to:**
- Documentation files (.md, .txt)
- Configuration files (.yml, .yaml, .json, .toml)
- Environment files (.env) in stacks
- Data files (.csv, .log)
- Makefile

**Reasoning:** Standard readable files. Owner can write, group and others can read.

### Shell Scripts (755 - rwxr-xr-x)

**Applies to:**
- All .sh files in scripts/
- Any executable scripts

**Reasoning:** Must be executable by owner, group, and others for automation and manual use.

### Appdata Directories (750 - rwxr-x---)

**Applies to:**
- appdata/ root directory
- All service subdirectories (authentik, grafana, postgres, etc.)
- All nested directories within service directories

**Reasoning:** Container data should be restricted to owner and docker group only. No world-readable access to application data.

**Exceptions:**
- vault/ - UID 100:GID 100 (container requirement, managed with sudo)

### Appdata Files (640 - rw-r-----)

**Applies to:**
- All files within appdata service directories
- Database files
- Configuration files
- Log files
- Cache files

**Reasoning:** Consistent with directory restrictions. Owner can write, docker group can read, no world access.

**Exceptions:**
- traefik/acme/acme.json - root:root 600 (security requirement, more restrictive)
- vault/ files - UID 100 ownership (container requirement, managed with sudo)

### Secrets Directories (750 - rwxr-x---)

**Applies to:**
- secrets/ root directory
- All subdirectories (authentik/, postgres/, cloudflare/, etc.)

**Reasoning:** Highly sensitive data must be restricted to owner and docker group only.

### Secrets Files (640 - rw-r-----)

**Applies to:**
- All secret files
- API keys
- Passwords
- Certificates
- Tokens

**Reasoning:** Owner can update secrets, docker group can read for containers, no world access.

## Quick Reference Table

| Type | Permission | Octal | Use Case |
|------|-----------|-------|----------|
| General directory | rwxr-xr-x | 755 | Code, docs, configs |
| General file | rw-r--r-- | 644 | Documentation, configs |
| Shell script | rwxr-xr-x | 755 | Executable scripts |
| Appdata directory | rwxr-x--- | 750 | Container data dirs |
| Appdata file | rw-r----- | 640 | Container data files |
| Secrets directory | rwxr-x--- | 750 | Secret directories |
| Secrets file | rw-r----- | 640 | Secret files |

## Setting Permissions

### For New Services

```bash
# Create appdata directory
mkdir -p /path/to/spoke/appdata/newservice
chown -R 1000:968 /path/to/spoke/appdata/newservice
find /path/to/spoke/appdata/newservice -type d -exec chmod 750 {} +
find /path/to/spoke/appdata/newservice -type f -exec chmod 640 {} +
```

### For New Scripts

```bash
# Create script
touch /path/to/spoke/scripts/maintenance/new_script.sh
chown 1000:968 /path/to/spoke/scripts/maintenance/new_script.sh
chmod 755 /path/to/spoke/scripts/maintenance/new_script.sh
```

### For New Secrets

```bash
# Create secret directory and file
mkdir -p /path/to/spoke/secrets/newservice
echo "secret_value" > /path/to/spoke/secrets/newservice/api_key
chown -R 1000:968 /path/to/spoke/secrets/newservice
chmod 750 /path/to/spoke/secrets/newservice
chmod 640 /path/to/spoke/secrets/newservice/api_key
```

## Container-Specific Ownership

Some containers require specific UIDs and cannot run as 1000:968:

### Vault (UID 100:GID 100)

Vault container runs as UID 100 and creates files with that ownership.

**Permissions:**
```bash
# Requires sudo
sudo chown -R 100:100 /path/to/spoke/appdata/vault
sudo find /path/to/spoke/appdata/vault -type d -exec chmod 750 {} +
sudo find /path/to/spoke/appdata/vault -type f -exec chmod 640 {} +
```

### Traefik acme.json (root:root 600)

Traefik's ACME certificate file must be root-owned with 600 permissions.

**Current state:**
```bash
ls -l /path/to/spoke/appdata/traefik/acme/acme.json
# -rw------- 1 root root 13302 Mar 23 2025 acme.json
```

**Note:** This is more restrictive than standard (640) and should be preserved.

### Postgres Tablespaces

May be root-owned in some configurations.

```bash
# If needed
sudo chmod 750 /path/to/spoke/appdata/library/postgres/tablespaces
```

## Verification Commands

### Check Directory Permissions

```bash
# Top-level Spoke directories (should be 755)
ls -la /path/to/spoke | grep "^d"

# Appdata directories (should be 750)
ls -la /path/to/spoke/appdata

# Secrets directories (should be 750)
ls -la /path/to/spoke/secrets
```

### Check File Permissions

```bash
# General files (should be 644)
find /path/to/spoke/docs -type f -exec stat -c "%a %n" {} \; | head

# Scripts (should be 755)
find /path/to/spoke/scripts -name "*.sh" -exec stat -c "%a %n" {} \;

# Appdata files (should be 640)
find /path/to/spoke/appdata/grafana -maxdepth 2 -type f -exec stat -c "%a %n" {} \; | head

# Secrets (should be 640)
find /path/to/spoke/secrets -type f -exec stat -c "%a %n" {} \; | head
```

### Check Ownership

```bash
# Should be your-user:docker (1000:968)
find /path/to/spoke -maxdepth 2 -exec stat -c "%U:%G %n" {} \; | grep -v "your-user:docker\|your-user:your-user"

# Check appdata for container-specific ownership
find /path/to/spoke/appdata -maxdepth 1 -type d -exec stat -c "%U:%G (UID:%u GID:%g) %n" {} \;
```

## Troubleshooting

### Permission Denied in Container

If a container reports permission denied:

1. Check container user in docker-compose.yml:
   ```yaml
   user: "1000:968"  # Should match your-user:docker
   ```

2. Check directory ownership:
   ```bash
   ls -la /path/to/spoke/appdata/servicename
   ```

3. Fix if needed:
   ```bash
   chown -R 1000:968 /path/to/spoke/appdata/servicename
   find /path/to/spoke/appdata/servicename -type d -exec chmod 750 {} +
   find /path/to/spoke/appdata/servicename -type f -exec chmod 640 {} +
   ```

### Container Requires Different UID

Some containers have hardcoded UIDs and cannot be changed:

1. Preserve the container's ownership (don't force 1000:968)
2. Ensure docker group (968) has read access if needed
3. Document in this file under "Container-Specific Ownership"

### Files Created with Wrong Permissions

If a container creates files with incorrect permissions:

1. Check if container runs as root (bad practice)
2. Consider adding `user: "1000:968"` to docker-compose.yml
3. If container must run as root, accept the root-owned files
4. Use sudo to fix permissions if needed

## Related Documentation

- `docs/acl_cleanup_summary.md` - ACL removal history and process
- `scripts/maintenance/cleanup_acls.sh` - ACL cleanup tool
- `CLAUDE.md` - Project standards and Docker configuration

## Maintenance

### After Adding New Service

```bash
# Set ownership
chown -R 1000:968 /path/to/spoke/appdata/newservice

# Set permissions
find /path/to/spoke/appdata/newservice -type d -exec chmod 750 {} +
find /path/to/spoke/appdata/newservice -type f -exec chmod 640 {} +
```

### Periodic Audit

```bash
# Find directories not 755 or 750
find /path/to/spoke -maxdepth 2 -type d ! -perm 755 ! -perm 750 -exec ls -ld {} \;

# Find appdata directories not 750
find /path/to/spoke/appdata -maxdepth 1 -type d ! -perm 750 -exec ls -ld {} \;

# Find files not 644, 640, 755, or 600
find /path/to/spoke/docs -type f ! -perm 644 -exec ls -l {} \;
find /path/to/spoke/appdata -maxdepth 3 -type f ! -perm 640 ! -perm 600 -exec ls -l {} \; | head
```

---

**Last Updated:** 2025-11-05
**Standard Version:** 1.0
**Status:** Active
