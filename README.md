# Spoke

<!--
==============================================================================
README.md - Spoke hub documentation
==============================================================================
Description: Hub-and-spoke self-hosted infrastructure platform overview
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

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/E1E21U3S1R)

A modular, open-source hub-and-spoke server platform for self-hosted infrastructure.

## What is Spoke?

Spoke provides a **hub** of core services (reverse proxy, authentication, database, security engine) and a **module** system where each service stack is an independent, opt-in repository. Clone Spoke, configure two files, and deploy only what you need.

## Architecture

```
spoke/
├── hub/                    # Core services (Traefik, Authentik, CrowdSec, PostgreSQL, Redis)
├── modules/                # Cloned module repos (gitignored)
├── shared/env/             # Site-specific environment files (gitignored)
├── secrets/                # All secrets (gitignored)
├── scripts/modules/        # Module management automation
└── Makefile                # Orchestrator
```

### Hub Services

| Service | Role |
|---------|------|
| socket-proxy | Secure Docker API access |
| traefik | Reverse proxy with automatic HTTPS, plugins |
| authentik | Single sign-on / authentication |
| crowdsec | WAF and intrusion prevention |
| postgres | Shared PostgreSQL database |
| redis | Shared cache and session store |

### Available Modules

Modules are independent repositories. Enable only the ones you need.

| Module | Description |
|--------|-------------|
| monitoring | Grafana, Prometheus, Loki, Telegraf, Dozzle, NUT UPS |
| database | InfluxDB3, MinIO |
| plex | Plex Media Server, Tautulli |
| piped | Piped backend, frontend, ytproxy + module-local Postgres (YouTube alt for LibreTube et al.) |
| immich | Self-hosted photo management |
| books | Audiobookshelf, Calibre |
| music | Navidrome, MusicBrainz Picard |
| torrenting | VPN-protected downloads (Gluetun, qBittorrent, Soulseek) |
| homepage | Homepage dashboard |
| foundryvtt | Foundry Virtual Tabletop |
| protonmail | ProtonMail Bridge |

## Quick Start

### Prerequisites

- Docker and Docker Compose v2
- Git
- GNU Make
- `openssl` (for local TLS cert generation)
- `yq` (Python wrapper: `pip install yq`) — needed for `modules.yml` parsing
- Your user must be in the `docker` group:
  ```bash
  sudo usermod -aG docker $USER
  # Log out and back in for group change to take effect
  ```

---

### Path A: Local Testing (no domain required)

Test Spoke on your machine with `spoke.local` — no DNS, no CDN, no CrowdSec account needed.

```bash
# 1. Clone the repo
git clone https://github.com/captainzonks/spoke.git
cd spoke

# 2. Initialize — creates directories, env files, generates secrets and TLS cert
make init-local

# 3. Add hosts entry (one time)
echo "127.0.0.1 spoke.local *.spoke.local" | sudo tee -a /etc/hosts

# 4. (Optional) Install mkcert for browser-trusted HTTPS instead of self-signed
mkcert -install
mkcert -cert-file secrets/tls/domain_1.pem \
       -key-file secrets/tls/domain_1.key \
       "*.spoke.local"
# Copy to domain_2 and domain_3 slots:
cp secrets/tls/domain_1.pem secrets/tls/domain_2.pem
cp secrets/tls/domain_1.key secrets/tls/domain_2.key
cp secrets/tls/domain_1.pem secrets/tls/domain_3.pem
cp secrets/tls/domain_1.key secrets/tls/domain_3.key

# 5. Build and deploy
make hub-deploy CROWDSEC_ENABLED=false

# 6. Access Authentik at https://auth.spoke.local
```

`make init-local` automatically:
- Sets `DOMAIN=spoke.local` and `CDN_IPS=` in `base.env`
- Sets `CROWDSEC_ENABLED=false` in `hub.env`
- Generates random passwords for PostgreSQL and Authentik
- Generates a self-signed wildcard certificate for `*.spoke.local`

---

### Path B: Production Setup

Deploy against a real domain with Cloudflare TLS and CrowdSec security.

```bash
# 1. Clone the repo
git clone https://github.com/captainzonks/spoke.git
cd spoke

# 2. Initialize — creates directories, copies example configs, detects PUID/DGID
make init

# 3. Edit configuration with your site-specific values
$EDITOR shared/env/base.env    # Domain, PUID, DGID, SPOKE_DIR, CDN_IPS, etc.
$EDITOR shared/env/hub.env     # Service versions, IPs, CROWDSEC_ENABLED=true
$EDITOR modules.yml            # Enable/disable modules

# 4. Create required secrets
#    Each file should contain the secret value with no trailing newline
echo -n 'your-postgres-password' > secrets/postgres/postgres_password
echo -n 'your-authentik-db-password' > secrets/postgres/authentik_psql_password
echo -n 'your-authentik-secret-key' > secrets/authentik/authentik_secret_key
echo -n 'your-crowdsec-lapi-key' > secrets/crowdsec/crowdsec_lapi_key
echo -n 'your-crowdsec-login' > secrets/crowdsec/crowdsec_online_api_login
echo -n 'your-crowdsec-password' > secrets/crowdsec/crowdsec_online_api_password
# Copy your TLS certificate and key (Cloudflare origin cert or Let's Encrypt):
cp /path/to/cert.pem secrets/tls/domain_1.pem
cp /path/to/cert.key secrets/tls/domain_1.key

# 5. Deploy hub services (CrowdSec enabled by default)
make hub-deploy

# 6. Deploy modules
make module-sync                    # Clone enabled module repos
make deploy MODULE=monitoring       # Deploy a specific module
# or
make deploy-all                     # Deploy hub + all enabled modules
```

See [docs/crowdsec.md](docs/crowdsec.md) for complete CrowdSec setup instructions.

## Usage

```bash
# Hub operations
make hub-deploy                     # Deploy hub services
make hub-health                     # Check hub health

# Module operations
make module-sync [MODULE=name]      # Clone/pull module repos
make deploy MODULE=name             # Deploy a module
make rebuild MODULE=name            # Rebuild a module
make logs MODULE=name               # View module logs
make health MODULE=name             # Check module health
make stop MODULE=name               # Stop a module
make down MODULE=name               # Stop and remove a module

# Bulk operations
make deploy-all                     # Deploy everything
make health-all                     # Health check everything
```

## Configuration

### `shared/env/base.env`

Instance-wide configuration: domain, timezone, user IDs, network ranges.
Copy from `base.env.example`.

### `shared/env/hub.env`

Hub service versions and network configuration.
Copy from `hub.env.example`.

### `modules.yml`

Module registry: which modules to deploy, their repos, and site-specific overrides (IPs, ports, secrets mapping).
Copy from `modules.yml.example`.

### Secrets

All secrets live in `secrets/` (gitignored). Each service documents which secrets it needs in its `stack.yml` manifest.

## Module Development

Each module repo contains:

- `docker-compose.yml` — Service definitions
- `.env.example` — Module-specific variables with defaults
- `stack.yml` — Module manifest (requirements, health checks)
- `traefik/` — Traefik routing rules (optional)

See [docs/module_development.md](docs/module_development.md) for the full module specification.

## Security

- **Traefik**: Custom build with startup reliability checks (validates network, socket-proxy, and optionally CrowdSec before starting)
- **CrowdSec**: AppSec WAF with behavioral analysis — opt-in via `CROWDSEC_ENABLED=true` (see [docs/crowdsec.md](docs/crowdsec.md))
- **Authentik**: Forward auth SSO for all protected services
- **Socket Proxy**: Restricted Docker API access (read-only by default)
- **Non-root containers**: All hub services run as non-root where supported
- **Docker secrets**: Passwords and keys mounted via `/run/secrets/`

## License

MIT
