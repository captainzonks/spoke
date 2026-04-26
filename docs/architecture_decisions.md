# Spoke: Architecture Decision Records

<!--
==============================================================================
architecture_decisions.md - Architecture decision records
==============================================================================
Description: Key architecture decisions and rationale
Author: Matt Barham
Created: 2026-02-12
Modified: 2026-04-22
Version: 1.0.1
==============================================================================
Document Type: Reference
Audience: Developer
Status: Active (living document)
==============================================================================
-->

## ADR-001: Hub-and-Spoke Architecture

**Decision**: Separate core infrastructure (hub) from application/service modules (spokes).

**Context**: The original monolith grew into a monolith mixing core orchestration with full application codebases. Applications like GeneGnome (34GB), Portfolio (1.6GB), and Daggerheart (848MB) have independent lifecycles.

**Rationale**:
- Each module can be versioned, deployed, and updated independently
- Users can pick only the modules they need
- Application repos (GeneGnome, Trekker, etc.) stay as their own repos
- Hub provides shared infrastructure that all modules depend on

**Consequences**:
- Need module management scripts for sync, validation, env generation
- Inter-service references must use well-known container names
- Traefik rules must be deployable per-module

## ADR-002: DNS/CDN Agnostic Design

**Decision**: No Cloudflare-specific services in the hub. TLS and CDN configuration is deployment-specific.

**Context**: The reference deployment uses Cloudflare for DNS, CDN, and origin certificates. Spoke should not require any specific CDN provider.

**Rationale**:
- Dropped cloudflare-tunnel from hub services
- TLS certificates referenced via environment variables, not hardcoded paths
- Traefik uses `{{ env "DOMAIN" }}` Go templating for domain references
- CDN IP ranges configurable via base.env

**Consequences**:
- Users must provide their own TLS certificates
- CDN-specific features (like Cloudflare WAF) are deployment-specific

## ADR-003: Environment Variable Merge Strategy

**Decision**: Three-layer env merge: base.env -> module .env.example -> modules.yml overrides.

**Context**: Need to support both hub-wide and module-specific configuration while keeping site-specific values out of public repos.

**Rationale**:
- `base.env` provides instance-wide defaults (domain, timezone, user IDs)
- Module `.env.example` provides module-specific defaults (image versions, container names)
- `modules.yml` overrides provide site-specific values (IPs, ports, custom config)
- Higher layers override lower layers

**Consequences**:
- `base.env` and `modules.yml` are gitignored (contain personal data)
- Only `.example` files are committed to public repos
- `generate_module_env.sh` handles the merge

## ADR-004: Module Manifest (stack.yml)

**Decision**: Each module declares its requirements in a `stack.yml` file.

**Context**: Need a machine-readable contract between modules and the hub.

**Rationale**:
- Enables automated validation before deployment
- Documents network, secret, and service dependencies
- Supports health check definitions
- Can be extended for future features (auto-discovery, web UI)

## ADR-005: Backward Compatibility with STACK= Variable

**Decision**: Makefile accepts both `MODULE=name` and `STACK=name` as aliases.

**Context**: The original system uses `STACK=` for all operations. During migration, muscle memory matters.

**Rationale**:
- Zero learning curve for the operator during transition
- Eventually `STACK=` can be deprecated after cutover

## ADR-006: Variable Naming - SPOKE_DIR

**Decision**: Use `SPOKE_DIR` as the primary directory reference variable.

**Context**: The platform needs a generic, meaningful directory variable name.

**Rationale**:
- `SPOKE_DIR` is meaningful for any deployment
- Modules reference `${SPOKE_DIR}` for portable path resolution
- `${SECRETS_DIR}` = `${SPOKE_DIR}/secrets/` for consistency

## ADR-007: Traefik Rules Deployment

**Decision**: Modules carry their own Traefik rules in a `traefik/` directory. A deployment script copies them to `appdata/traefik/rules/` with a `mod_` prefix.

**Context**: Traefik watches a single rules directory. Multiple modules need to deploy rules without conflicts.

**Rationale**:
- `mod_` prefix prevents naming collisions between modules
- Traefik auto-detects new files (no restart needed)
- Hub owns generic middleware; modules own their own routers/services
- Easy to identify which rules belong to which module

## ADR-008: Standalone-First External Module Design

**Decision**: External modules (repos not purpose-built for Spoke) must work standalone without any Spoke knowledge. All Spoke adaptation happens at the boundary via `modules.yml` env_overrides and secrets_map.

**Context**: GeneGnome is a public open-source repo whose GitHub page serves as the trust anchor for its security claims. Users audit the repo to verify data handling. Leaking hub-specific conventions (hub-specific IPs, Spoke variable names, provider-specific secret paths) into the public repo undermines auditability and creates false dependencies.

**Rationale**:
- Public repos must be clean, self-documenting, and auditable without Spoke context
- Generic variable names (`IMAGE_PREFIX`, `PROXY_NETWORK`, `SECRETS_DIR`) work for any deployment
- Traefik middleware chains are fully self-contained (no hub dependencies like CrowdSec/Authentik)
- Hub security middleware can be appended by the operator (documented in comments)
- Secret paths use generic conventions (`smtp/smtp_password`), Spoke remaps to actual paths (`proton/proton_bridge_password`)
- Module uses its own naming conventions (`_VERSION` not `_TAG`), Spoke adapts

**Consequences**:
- `modules.yml` env_overrides must translate between module and instance variable names
- `secrets_map` remaps generic secret paths to instance-specific paths
- Traefik rules work out of the box but lack CrowdSec/Authentik — operator adds per deployment
- Slightly more env_overrides entries compared to official modules, but clean public repos

## ADR-009: Single GID (Docker Group) for All Containers

**Decision**: Use the host docker group GID (`DGID`) as the group for all hub containers, not just socket-proxy.

**Context**: Only socket-proxy strictly requires the docker group GID (for `/var/run/docker.sock` read access). Other services (postgres, redis, traefik, crowdsec, authentik) work with any GID as long as file ownership is consistent.

**Rationale**:
- Simplifies the model: one `DGID` variable, one group across the board
- No need for separate "app group" vs "docker group" variables
- File ownership stays consistent across all appdata directories
- Dockerfiles are already parameterized via `USER_ID`/`GROUP_ID` build args — changing DGID in base.env propagates automatically
- Default changed from 1000 to 999 (Debian/Ubuntu common) with distro-specific documentation

**Consequences**:
- Users must set DGID correctly via `getent group docker | cut -d: -f3` or `make init` auto-detect
- All container volumes are owned by PUID:DGID
- If a user changes DGID after initial deployment, existing appdata may need `chown`

## ADR-010: Comprehensive Init Over Minimal Bootstrap

**Decision**: `make init` performs full environment scaffolding (auto-detect, directories, example copying, secrets checklist) rather than just creating Docker networks.

**Context**: Phase 6 cutover testing revealed that fresh installs required many manual steps not documented in one place: creating directories, copying examples, setting DGID correctly, creating secret files. Docker would create missing directories as root, causing permission failures.

**Rationale**:
- Pre-creating `appdata/traefik/plugins-storage/` as the current user prevents Docker from creating it as root (which breaks Traefik plugin loading)
- Auto-detecting PUID/DGID eliminates the most common misconfiguration
- Copying example files removes a manual step that's easy to forget
- Listing required secrets with a missing count gives clear progress indication
- All directory creation runs as the current user (no sudo needed)

**Consequences**:
- `make init` is idempotent — safe to run multiple times
- Existing files are never overwritten (only copies if target missing)
- Users get actionable warnings if docker group is missing or they're not a member

## ADR-011: Traefik Audit via Temp Files, Not String Accumulation

**Decision**: The Traefik rule audit in `deploy_traefik_rules.sh` uses temp files and `grep -qx` for cross-referencing, not bash string accumulation.

**Context**: The original audit collected `@file` references and definitions into bash variables using `defined="${defined} $(awk ...)"`. This corrupted whitespace, producing false positives where defined names couldn't be matched.

**Rationale**:
- Pipe awk output directly to sorted temp files — no variable expansion issues
- `grep -qx` does exact-line matching against the definitions file
- Comment lines filtered with `grep -v '^[[:space:]]*#'` before reference extraction
- Definitions collected from ALL deployed rule files; references only from the current module

**Consequences**:
- Temp directory created with `mktemp -d` and cleaned via trap
- Audit is accurate even with large rule sets across many modules

## ADR-012: Resolve Docker Network Names from Compose Config

**Decision**: `validate_module.sh` resolves actual Docker network names from `docker compose config` output when `.env` is present, falling back to `stack.yml` literal names otherwise.

**Context**: External modules use generic variable names (`PROXY_NETWORK=proxy`) that get overridden to actual network names (`troxy`) via `modules.yml` env_overrides. Validating the literal stack.yml name produces false failures.

**Rationale**:
- `docker compose config` expands all environment variables, showing the real network names
- The `name:` field in compose output is the actual Docker network name (not the YAML key)
- Without `.env`, fall back to stack.yml names (best-effort for dry-run validation)

**Consequences**:
- Validation requires `.env` to be generated first for accurate results (normal deploy flow)
- External modules with env_overrides validate correctly

## ADR-013: Explicit Network Names to Prevent Project Prefix Doubling

**Decision**: Module compose files that define internal networks must include explicit `name:` fields to prevent Docker Compose from prepending the project name.

**Context**: GeneGnome's compose file defined `genetics_isolated` and `genetics_db_network` as network keys. Docker Compose prepends the project name (`genetics`) to keys, producing `genetics_genetics_isolated`.

**Rationale**:
- Adding `name: genetics_isolated` tells Docker Compose the exact network name to use
- No project name prefix is added when `name:` is explicit
- Matches the pattern already used for external networks (hub networks always have `name:`)

**Consequences**:
- All module-internal networks must include `name:` fields
- Existing containers may need recreation if network names change

## ADR-014: Envsubst Module Variables into Traefik Rule YAMLs

**Decision**: `deploy_traefik_rules.sh` (>= 1.3.0) sources the module's generated `.env`, builds an allowlist from its keys, and runs `envsubst` over each rule YAML before copying it into `appdata/traefik/rules/`. Rule YAMLs without any `${VAR}` placeholders are passed through unchanged.

**Context**: Spoke's runtime `{{ env "X" }}` Traefik template only sees variables that exist in the Traefik *container's* environment. Module-level variables — defined in the module's `.env.example` and overridable per site via `modules.yml env_overrides` — never reach Traefik through the normal flow. This forced any per-site customisation of router rules (subdomain prefix, path prefix, custom headers) to live as a literal in the module repo, which made site-level rebrands impossible without forking.

The first concrete case was `spoke-piped`: a site wanted `tube.${DOMAIN}` instead of the upstream `piped.${DOMAIN}`, and there was no clean way to express the override without modifying the module repo.

**Rationale**:
- `envsubst` operates *during deployment*, while the module `.env` is in scope, so module vars cleanly flow into the rule YAMLs the Traefik file provider eventually parses
- Building the allowlist from the module `.env` keys keeps substitution scoped — only module-level `${VAR}` patterns are touched; hub or unrelated `${...}` strings pass through verbatim
- Rule YAMLs without placeholders fall through unchanged → fully backwards compatible with all pre-1.3.0 modules
- Two-stage substitution (`${VAR}` at deploy time, `{{ env "X" }}` at runtime) keeps the boundary between module-level config (shipped per module) and instance-level config (set by the hub) explicit

**Consequences**:
- Modules can ship generic Traefik defaults (e.g. `Host(\`${MYMODULE_SUBDOMAIN}.{{ env "DOMAIN" }}\`)` with `MYMODULE_SUBDOMAIN=mymodule` in `.env.example`) and let sites override the prefix once in `modules.yml env_overrides`
- A module variable referenced as `${VAR}` but missing from the module's `.env` (or `.env.example` + `modules.yml`) will be substituted with an empty string → defensive practice is to always declare the default in `.env.example` first
- `envsubst` must be on PATH; the script falls back to plain `cp` when it isn't, which leaves literal `${VAR}` tokens in the deployed YAML and breaks the route. A future improvement is to log a warning when fallback triggers
