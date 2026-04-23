# Spoke Scripts

<!--
==============================================================================
README.md - Spoke scripts documentation
==============================================================================
Description: Module lifecycle + routine maintenance scripts for Spoke
Author: Matt Barham
Created: 2026-02-12
Modified: 2026-04-22
Version: 1.0.1
==============================================================================
Document Type: Reference
Audience: Developer
Status: Final
==============================================================================
-->

## Overview

Scripts for managing Spoke modules and performing routine maintenance.

## Directory Structure

```
scripts/
├── modules/              # Module lifecycle scripts (used by Makefile)
│   ├── deploy_hub_rules.sh
│   ├── deploy_traefik_rules.sh
│   ├── generate_module_env.sh
│   ├── provision_hub_postgres.sh
│   ├── sync_modules.sh
│   └── validate_module.sh
├── maintenance/          # Operational maintenance scripts
│   ├── crowdsec_weekly_summary.sh
│   ├── crowdsec_weekly_summary.service
│   ├── crowdsec_weekly_summary.timer
│   ├── manage_crowdsec_scenarios.sh
│   ├── portfolio_cleanup.sh
│   ├── portfolio_cleanup.service
│   ├── portfolio_cleanup.timer
│   ├── restart_vpn_stack.sh
│   └── secrets_newline_cleanup.sh
└── README.md
```

## Module Scripts

These are called by the Makefile during module operations. You typically don't run them directly.

| Script | Purpose |
|--------|---------|
| `deploy_hub_rules.sh` | Deploy Traefik rules from hub to appdata |
| `deploy_traefik_rules.sh` | Deploy module-specific Traefik dynamic rules |
| `generate_module_env.sh` | Generate merged .env files for modules from base + module vars |
| `provision_hub_postgres.sh` | Create databases and users in the hub Postgres instance |
| `sync_modules.sh` | Sync module definitions from `modules.yml` |
| `validate_module.sh` | Validate module structure, compose file, and network references |

## Maintenance Scripts

### Systemd Timer Units

| Unit | Schedule | Purpose |
|------|----------|---------|
| `crowdsec_weekly_summary.service` | — | Send CrowdSec threat summary email via ProtonMail Bridge |
| `crowdsec_weekly_summary.timer` | Sun 20:00 | Trigger weekly summary |
| `portfolio_cleanup.service` | — | Delete old portfolio form submissions from Postgres |
| `portfolio_cleanup.timer` | Daily 03:00 | Trigger daily cleanup |

### Other Scripts

| Script | Purpose |
|--------|---------|
| `restart_vpn_stack.sh` | Stop VPN-dependent containers, restart Gluetun, wait healthy, restart deps |
| `manage_crowdsec_scenarios.sh` | Interactive CrowdSec management: alerts, decisions, whitelists, simulation |
| `secrets_newline_cleanup.sh` | Remove trailing newlines from Docker secrets files (with backup + verify) |

## Installing Systemd Timers

1. Copy the `.service` and `.timer` files to `/etc/systemd/system/`:

   ```bash
   sudo cp scripts/maintenance/<unit>.service /etc/systemd/system/
   sudo cp scripts/maintenance/<unit>.timer   /etc/systemd/system/
   ```

2. Edit the `.service` files to update paths and user:
   - Replace `/path/to/spoke/` with your actual Spoke installation path
   - Update `User=` if your username differs

3. Enable and start:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now <unit>.timer
   ```

4. Verify:

   ```bash
   systemctl list-timers --all | grep -E 'crowdsec|portfolio'
   ```
