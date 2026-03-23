# Docker Log Helper Functions

<!--
==============================================================================
docker_log_functions.md - Docker log helper ZSH functions reference
==============================================================================
Description: ZSH functions for quick Docker container log access
Author: Matt Barham
Created: 2026-01-23
Modified: 2026-03-14
Version: 1.1.0
==============================================================================
Document Type: Reference
Audience: Developer
Status: Final
==============================================================================
-->

## Overview

ZSH functions for quick and easy Docker container log access, located at:
`~/.config/zsh/features/55-docker-functions.zsh`

These functions replace the need for repetitive `docker logs` and `make logs MODULE=...` commands with shorter, more convenient aliases.

## Functions

### `dlog` - Docker Logs

Quick access to single or multiple container logs with combined output.

**Usage:**
```bash
dlog <container>                # Follow single container logs
dlog <container1> <container2>  # Follow multiple containers
dlog -s <container>             # Show without following
dlog -n 100 <container>         # Show last 100 lines
dlog -t 5m <container>          # Show logs from last 5 minutes
```

**Options:**
- `-s, --static` - Show logs without following (static output)
- `-n, --tail N` - Show last N lines only
- `-t, --since TIME` - Show logs since time (e.g., 5m, 1h, 2h30m)
- `-h, --help` - Show help message

**Examples:**
```bash
# Single container
dlog traefik                     # Follow Traefik logs
dlog -n 50 plex                  # Show last 50 lines from Plex
dlog -t 1h grafana               # Show Grafana logs from last hour
dlog -s authentik                # Show Authentik logs (don't follow)

# Multiple containers
dlog traefik crowdsec            # Follow both containers (combined output)
dlog traefik crowdsec authentik  # Follow three containers
```

**Smart Behavior:**
- **Same compose project:** If all containers are from the same Docker Compose project (hub or a single module), uses `docker compose logs` for properly interleaved output
- **Different projects:** Runs `docker logs` in parallel with container name prefixes

### `dps` - Docker PS (Better Formatting)

Improved `docker ps` with cleaner output format.

**Usage:**
```bash
dps                  # Show all running containers
dps -a               # Show all containers (including stopped)
dps <filter>         # Filter by name
```

**Examples:**
```bash
dps                  # List running containers
dps -a               # List all containers
dps traefik          # Show only Traefik container
```

### `dexec` - Docker Exec (Quick Shell Access)

Quick shell access to containers.

**Usage:**
```bash
dexec <container>           # Open sh/bash shell in container
dexec <container> bash      # Open bash specifically
dexec <container> <command> # Run specific command
```

**Examples:**
```bash
dexec traefik               # Open shell in Traefik container
dexec postgres-hub psql -U user  # Run psql in hub postgres
dexec authentik bash        # Open bash shell in Authentik
```

**Smart Shell Selection:**
- Automatically tries `bash` first
- Falls back to `sh` if bash not available
- Always uses interactive terminal (`-it`)

### `dreset` - Quick Container Restart

Quick container restart shortcut.

**Usage:**
```bash
dreset <container>  # Restart a container
```

**Examples:**
```bash
dreset traefik      # Restart Traefik
dreset plex         # Restart Plex
```

## Tab Completion

All functions support tab completion for container names:

```bash
dlog <TAB>          # Shows list of running containers
dexec <TAB>         # Shows list of running containers
dreset <TAB>        # Shows list of running containers
```

## Comparison with Makefile

**Before (Makefile):**
```bash
make hub-logs SERVICE=traefik SINCE=1h   # Hub service logs
make logs MODULE=monitoring              # All monitoring containers
make logs MODULE=monitoring SERVICE=grafana  # Just Grafana
```

**After (ZSH Functions):**
```bash
dlog traefik crowdsec authentik  # Follow multiple containers
dlog traefik                     # Just Traefik
dlog -n 50 traefik               # Last 50 lines
dlog -t 1h grafana               # Last hour of Grafana logs
```

**Benefits:**
- ✅ Shorter commands
- ✅ Tab completion
- ✅ Mix containers from different modules
- ✅ More flexible filtering options
- ✅ Faster for single container access

**When to use Makefile:**
- Need all containers in a hub/module
- Part of automated scripts
- Prefer explicit hub/module specification

**When to use ZSH functions:**
- Interactive terminal use
- Quick single container access
- Following multiple specific containers across modules
- Need recent log filtering

## Installation

The file is automatically loaded by ZSH from:
`~/.config/zsh/features/55-docker-functions.zsh`

**To reload without restarting shell:**
```bash
source ~/.config/zsh/features/55-docker-functions.zsh
```

Or restart your shell:
```bash
exec zsh
```

## Technical Details

### Multi-Container Log Handling

When following multiple containers:

1. **Same Compose Project Detection:**
   - Checks `hub/docker-compose.yml` for hub services
   - Checks `modules/*/docker-compose.yml` for module services
   - Runs `docker compose ps` to get container lists per project
   - If all containers belong to the same project, uses `docker compose logs`

2. **Different Projects:**
   - Runs `docker logs` for each container in parallel
   - Prefixes each line with `[container-name]`
   - Interleaves output in real-time

### Performance Considerations

- Single container: Direct `docker logs` (minimal overhead)
- Same compose project: `docker compose logs` (optimal interleaving)
- Different projects: Parallel processes (slight overhead from prefixing)

## Examples by Use Case

### Debugging Traefik Issues
```bash
# Follow Traefik logs
dlog traefik

# Follow Traefik + CrowdSec together
dlog traefik crowdsec

# Check last 100 lines for errors
dlog -n 100 traefik | grep -i error

# Recent logs only
dlog -t 10m traefik
```

### Monitoring Multiple Services
```bash
# Follow entire hub security stack
dlog traefik crowdsec authentik

# Follow media services
dlog plex tautulli

# Mix hub + module containers
dlog postgres-hub redis grafana
```

### Quick Health Checks
```bash
# Static output (don't follow)
dlog -s -n 20 authentik

# Last hour of activity
dlog -t 1h -s plex

# Recent errors
dlog -t 30m plex | grep -i error
```

---

**Document Version**: 1.1.0
**Last Updated**: 2026-03-14
**Author**: Matt Barham
**Host**: Your Server
