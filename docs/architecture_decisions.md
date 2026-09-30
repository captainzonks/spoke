# Spoke: Architecture Decision Records

<!--
==============================================================================
architecture_decisions.md - Architecture decision records
==============================================================================
Description: Key architecture decisions and rationale
Author: Matt Barham
Created: 2026-02-12
Modified: 2026-09-30
Version: 1.2.0
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

## ADR-021: No Deploy CI on a Single Node

**Decision**: Spoke has no build-and-deploy CI. Changes are promoted to the running deployment by hand: merge in the hub or module repo, pull into the deployed instance (`git pull` for the hub, `make module-sync MODULE=<name>` for modules), then run the Makefile targets that wrap `docker compose` (`make hub-deploy` / `hub-rebuild`, `make deploy` / `rebuild` / `recreate MODULE=<name>`). CI jobs that only test or scan code on GitHub-hosted runners are allowed, because they deploy nothing and never touch the host.

**Context**: A Jenkins plus Git build-and-deploy pipeline was evaluated and rejected. The deployment is a single node. The hub's `socket-proxy` (`wollomatic/socket-proxy`) is the only container that mounts `/var/run/docker.sock`; every other container that needs the Docker API reaches it over the `soxy` network, and the proxy only forwards requests that match its per-verb path allowlists (`CONNECT`, `TRACE` and `OPTIONS` are denied outright). Since ADR-023 the shared proxy is read-only and the one writer (Sablier) has its own narrowly scoped instance; at no point have the allowlists included image builds (`/build`) or pulls (`/images/create`). The hub also now runs `.github/workflows/gitleaks.yml`, a scan-only job, so this record has to separate deploy CI (rejected) from test and scan CI (allowed).

**Rationale**:
- A build-and-deploy runner on this node needs to build images and restart services, which means the Docker API calls the socket-proxy allowlists exist to withhold. Granting them to a runner would reintroduce, for one more long-running service, the privilege the socket-proxy architecture was built to deny.
- A deploy runner hosted on the node it deploys to is circular: it can't reliably restart the stack it lives inside.
- With one node, the options were to weaken the security model or to accept manual promotion. Manual promotion keeps the security model intact.
- Test and scan jobs on GitHub-hosted runners are a different case: the runners are ephemeral, hold no deployment credentials, and have no path to the host or its Docker socket. `spoke-triage` ADR-019 ("Test-Only CI, No Deploy CI") applies the same distinction to that module's `ci.yml`.

**Alternatives Considered**:
- **Jenkins or a self-hosted GitHub Actions runner on the host**: rejected. Either needs direct Docker socket access (or a proxy allowlist broad enough to be equivalent) and has the circular-restart problem above.
- **A runner restricted by a scoped socket-proxy allowlist**: rejected. Deploying requires at least `/build` or `/images/create` plus container create and restart. Container create with an arbitrary host config (privileged mode, host bind mounts) is effectively root on the host, so a scoped allowlist that still permits deployment is not a meaningful restriction.
- **Manual promotion**: chosen.

**Consequences**:
- Every deploy is a deliberate operator action on the host. Nothing reaches the running deployment without someone running the Makefile.
- The cost is operator time and discipline: no automatic rollout after merge, no automated rollback, and the deployed instance can lag `main` until someone pulls and redeploys. Nothing automatically signals drift between the repo and the deployment.
- Verification after a deploy (health checks, logs) is manual, using `make health`, `make hub-health` and `make logs`.
- Test and scan CI (hub `gitleaks.yml`, `spoke-triage` `ci.yml`) stays in scope and may grow, provided it keeps to GitHub-hosted runners, read-only permissions and no deployment credentials.

**Revisit When**:
- A second node exists. A runner there could deploy to this node over an authenticated, scoped channel without access to this host's Docker socket, and would not be restarting the stack it runs inside.

## ADR-023: Read-Only Shared Socket Proxy, Dedicated Proxy for the One Writer

**Decision**: The hub `socket-proxy` (`wollomatic/socket-proxy` 1.13.1) is read-only for every client on the `soxy` network: `SP_ALLOW_GET` and `SP_ALLOW_HEAD` from `hub.env`, with `SP_ALLOW_POST`, `SP_ALLOW_PUT` and `SP_ALLOW_DELETE` fixed to `NONE` in `hub/docker-compose.yml`. The one client that writes, `sablier`, talks to its own instance, `socket-proxy-sablier` (`SPROXY_SABLIER_IP`, 192.168.33.11). That instance accepts connections only from `SABLIER_IP_S/32` and allows the same GET/HEAD lists plus `POST` to `containers/<name>/(start|stop|wait)`.

**Context**: The previous configuration applied one allowlist to the whole `192.168.33.0/24` network, and it included `containers/create`, container start/stop/restart/wait, `containers/*/update`, `DELETE containers/*` and the prune endpoints. Every `soxy` client could therefore create a container, including crowdsec, traefik (internet-facing), telegraf, alloy, both dozzle instances and authentik-worker. `containers/create` accepts an arbitrary host config (privileged mode, host bind mounts, host namespaces), so any one of those services being compromised was a path to root on the host. The `:ro` flag on the socket bind mount does not limit the API. The broad list dated from the repo's initial commit, with no recorded reason for the write verbs.

**Rationale**:
- Of the eight clients, only Sablier writes. Its Docker provider (v1.16.1 source, `pkg/provider/docker`) calls `ContainerStart`, `ContainerStop` and `ContainerWait` under the default `stop` strategy. `ContainerPause`/`ContainerUnpause` are used only by the `pause` strategy and `ContainerUpdate` only by resource profiles; Rome configures neither. Everything else reads: traefik's Docker provider, crowdsec's Docker acquisition, alloy and dozzle log streaming, telegraf's Docker input, and authentik-worker's service-connection health check. Authentik's only outpost is the embedded one, so no managed outpost container is ever created through the proxy.
- A second proxy instance makes Sablier's permissions a static property of that instance's environment, with nothing to resolve at request time. Its `SP_ALLOWFROM` is Sablier's single IP, so no other client can reach its write verbs.
- `NONE` is compiled to `^NONE$`, which no API path can match, so it denies the verb outright. That is the idiom the file already uses for `CONNECT`, `TRACE` and `OPTIONS`. Hardcoding it in the compose file, rather than reading it from `hub.env`, means a site config can't quietly widen the shared proxy again.

**Alternatives Considered**:
- **Keep one network-wide allowlist and drop only `create`**: rejected. Every client would still be able to stop, restart or delete any container, which is a denial-of-service path from any compromised service.
- **Per-container allowlists via Docker labels on the shared proxy** (`SP_PROXYCONTAINERNAME`, socket-proxy ≥ 1.11): deployed first and rolled back the same day. socket-proxy registers a label allowlist when it handles the container's Docker `start` event. On Rome that took between 0.5 and 5 seconds, and Sablier calls `stop` on idle instances within that window of starting, so those calls matched the read-only default and were refused on every Sablier start. Removing Sablier's IP from `SP_ALLOWFROM`, so that its requests take socket-proxy's synchronous-refresh path, was worse: the refresh did not find the just-started container, Sablier's startup ping got `forbidden IP`, and Sablier could not start.
- **`SP_ALLOWBINDMOUNTFROM` bind-mount restrictions**: not needed. The upstream README calls it a request filter, not a sandbox (it does not block privileged mode, host namespaces or devices), and neither proxy grants `create`.

**Consequences**:
- A new service that needs Docker write access gets its own proxy instance scoped to its IP, following `socket-proxy-sablier`; adding write verbs to `hub.env` has no effect. Write calls to the shared proxy get `403 Forbidden` and are logged as `blocked request` (`path not allowed`).
- One more small container (64 MB limit, read-only filesystem, all capabilities dropped, same image and pin as `socket-proxy`), and 192.168.33.11 reserved on `soxy`.
- If Rome ever deploys a Docker-managed Authentik outpost, authentik-worker will need `containers/create`, start/stop and delete. Give it a dedicated instance too, and treat that container as host-root-equivalent.
- A Sablier upgrade that starts using another endpoint (for example `pause`) will fail visibly with blocked requests rather than silently; review Sablier's release notes before upgrading.

## ADR-024: modules.yml Key Order Is Boot Deploy Order; `boot_deploy: false` Opts Out

**Decision**: `boot_deploy.sh` Phase 4 deploys enabled modules in the key order they appear in `modules.yml`, and that order is load-bearing: a module whose services consume another module's services must be listed after it. A module may set `boot_deploy: false` to be skipped at boot entirely; an absent key means true. `modules.yml.example` documents both, lists `database` before `monitoring`, and marks `triage` as `boot_deploy: false`.

**Context**: Rome rebooted on 2026-09-25. `modules.yml` listed `monitoring` first and `database` thirteenth, so Loki started at 23:02:39 UTC pointed at a MinIO that did not start until 23:08:46 UTC. Loki logged 114 `failed to build table names cache` errors against `192.168.35.42:9000` — first `no route to host` while the container was off the bridge, then `connection refused` once it was up but not yet listening — restarted once at 23:09:46 UTC, and recovered. Alloy then dropped three backup-orchestrator batches that Loki rejected as too old. The next morning's triage report raised two HIGH findings recommending a MinIO restart, for a service that had been healthy for hours.

The same boot also deployed `triage` at 17:14:36 MDT, whose collector opened run 26. The 06:02 timer opened run 27 the next morning, and the analyst claimed 27 and abandoned 26 (spoke-triage ADR-020). Run 26's window covered the reboot, so the boot-time run produced nothing and was discarded.

**Rationale**:
- Compose `depends_on` and `condition: service_healthy` are scoped to one compose project. Modules are separate projects by design (ADR-001), so there is no in-Compose way to express that Loki needs MinIO. Deploy order is the only ordering primitive Spoke has.
- The dependency is real and one-way: Loki and Prometheus store chunks in MinIO, Telegraf writes InfluxDB3, Grafana reads VictoriaMetrics. Nothing in `database` references a `monitoring` service, so `database` can always be listed first without a cycle.
- Key order is already how the script iterates; `yq`'s `to_entries` preserves document order. Making the order meaningful costs nothing and needs no new syntax — but it is invisible unless written down, which is what this ADR and the `modules.yml.example` comments are for.
- `boot_deploy: false` is expressed as an opt-out rather than an opt-in so existing `modules.yml` files keep their behaviour with no edit. The filter is `select(.value.boot_deploy != false)`, and a missing key is `null`, which is not `false`.
- Skipped modules are logged by name before the deploy loop runs. A module that is enabled but absent from the boot log would otherwise be indistinguishable from a module that failed to deploy.

**Alternatives Considered**:
- **Retry or healthcheck gate in `monitoring`**: rejected. Loki already retries; the errors are the retries. A gate would move the wait into the monitoring module without fixing the ordering, and would have to hardcode a `database` service name inside `monitoring`, breaking module isolation.
- **A `depends_on_modules` key with a topological sort**: correct in general, but it adds a dependency graph and cycle detection to a boot script for one edge that a documented order already handles. Revisit if a second cross-module edge appears that ordering cannot express.
- **Suppress the findings in `known_patterns.md` instead**: rejected as the primary fix. The findings were accurate; the boot race was real and cost roughly six minutes of log ingestion per reboot. A pattern entry teaches the analyst to report boot-window clusters as INFO, which is worth doing, but it is not a substitute for removing the race.
- **Leave `triage` in the boot deploy**: rejected. It is a batch job whose systemd timer owns its schedule. A boot-time run costs a collector pass over Loki and produces a run the next timed run supersedes.

**Consequences**:
- Inserting a new module into `modules.yml` is an ordering decision, not an append. The `MODULE ORDER MATTERS` block in `modules.yml.example` names the known consumer edge so it is visible at the point of edit.
- `make deploy-all` walks the same key order, so the dependency ordering holds there too. It deliberately does **not** honour `boot_deploy: false`: the flag is scoped to unattended boot, and an operator typing `deploy-all` is asking for everything. A module skipped at boot is still deployed by `make deploy-all` and by `make deploy MODULE=name`.
- The `yq`-less fallback path cannot read `modules.yml` and therefore cannot honour `boot_deploy: false`. It now logs a warning saying so rather than quietly deploying everything.
- A module marked `boot_deploy: false` will not come up after a reboot until its own timer fires. That is correct for a batch job and wrong for a service; the key must not be used to work around a slow or flapping service.

## ADR-029: Semantic Versioning for the Hub and Every Module, Released from Signed Tags

**Decision**: The hub and every module repo, GeneGnome included, are versioned with [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). A release is a GPG-signed annotated tag `vX.Y.Z` on `main`, a GitHub Release with the same notes, and a `CHANGELOG.md` entry in [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) form. The tag is the source of truth. Every other place that states a release version has to equal it: `Cargo.toml`, `pyproject.toml` and `package.json` versions (repo root and immediate subdirectories), `stack.yml` `module.version`, and the tags of images the repo builds itself, which `.env.example` lists on a `# @release-version:` line. `scripts/maintenance/release.sh` cuts releases in two steps, `prepare` (release PR) and `publish` (tag and GitHub Release), using the shared `cliff.toml`. A deployment pins each module to a release with `ref: vX.Y.Z` in `modules.yml`.

**Context**: On 2026-09-27 none of the 26 repos had a tag or a release. Versions existed in several places and none of them was maintained:
- `spoke-triage` declared Cargo `0.3.0`, last bumped at `110fc38`. Eight fixes landed after it, including the `Secret` type (spoke-triage ADR-026), the removal of prompt caching (ADR-027) and the collector egress guard (ADR-028), and none of them bumped it. Its image tags in `.env.example` still said `0.1.0`.
- GeneGnome's `stack.yml` said `1.4.1` while its three crates and its image tags said `1.2.0`.
- Seven other modules carried a `stack.yml` `module.version` (`1.0.0` in most), unchanged since it was written. `spoke-hoa`'s `pyproject.toml` said `0.1.0`, and `spoke-portfolio`'s form handler crate and OAuth proxy `package.json` said `1.0.0`. The remaining fifteen repos, the hub included, had no version anywhere.
- The only version fields that were edited were the per-file header `Version:` lines. Those record revisions of one file, not releases of a repo.
- `sync_modules.sh` ran `git checkout "${ref}"` then `git pull origin "${ref}"`. With a tag as `ref` the checkout would leave a detached HEAD and the pull would fail, so every deployment tracked `main`. The code running on the host was "whatever `main` was at the last `make module-sync`", which is not recorded anywhere.

**Rationale**:
- **A Compose module's public API is its contract with the deployment**, since that is what an upgrade can break. SemVer needs the public API declared. For a Spoke module it is: the variable names in `.env.example`, the `secrets_map` keys its compose file expects, its service, container and network names, its volume and appdata layout, and the hub services and `modules.yml` keys it needs.
  - **MAJOR**: something in that contract is removed or renamed, or upgrading needs a manual step (a data migration, a new secret the operator must create, a `modules.yml` edit).
  - **MINOR**: something is added that existing deployments can ignore: a new service, an optional variable, a feature.
  - **PATCH**: fixes, and upstream image bumps that leave the contract unchanged. An upstream image bump that needs a migration is MAJOR, whatever the upstream version change was.
  - For Rust crates and the images built from them, the Cargo meaning of the version applies as well.
  - Below 1.0.0 (SemVer item 4), a breaking change bumps MINOR, following the Cargo convention; `cliff.toml` sets `breaking_always_bump_major = false` for this.
- **Signed tags, not an in-repo version file, as the source of truth.** The hub already signs every commit and its rulesets require signatures. A signed annotated tag extends that to the release, and `git verify-tag` can check it. A `VERSION` file would be one more copy to drift. The copies that have to exist (package manifests, `stack.yml`, image tags) are written by `release.sh prepare` in the same commit as the changelog entry, so they cannot drift at a release.
- **Changelog generated from commits already written.** Every repo uses conventional-commit subjects and squash-merges, so `main` is a list of PR titles typed `feat`, `fix`, `refactor` and so on. [git-cliff](https://git-cliff.org/) turns those into the entry, and `--bumped-version` computes the next version from them (`feat` → MINOR, `fix` → PATCH, `!` or `BREAKING CHANGE` → MAJOR). A version can still be given explicitly, which it must be when a contract change was committed under a type that does not signal it.
- **Two-step release, because `main` only accepts PRs.** The rulesets block direct pushes to `main`, and the hub rule is that nothing merges until every check is green. `prepare` opens a normal PR from the operator's own account, so the required checks run on it. `publish` runs after the merge, finds the squash-merge commit `chore(release): vX.Y.Z (#N)` on `main`, and tags that commit, not whatever `main` has moved on to.
- **Pinning to tags applies ADR-021 to module versions.** Promotion is already a deliberate operator action. Pinning makes the promoted version explicit and recorded in `modules.yml`: upgrading a module means changing its `ref` after reading its changelog, then `make module-sync` and a redeploy.

**Alternatives Considered**:
- **release-please** ([googleapis/release-please-action](https://github.com/googleapis/release-please-action) v5.0.0): rejected for now. It opens release PRs with the workflow's `GITHUB_TOKEN`, and [events created with that token do not start new workflow runs](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication#using-the-github_token-in-a-workflow). On repos with required checks (`spoke`, `spoke-triage`) its release PRs would never go green. The workaround is a GitHub App or a fine-grained PAT stored as a repo secret, which is one more long-lived credential to manage. It also creates unsigned lightweight tags.
- **A `VERSION` file per repo**: rejected. It is another copy of the version, and the tag already exists.
- **Tag everything `1.0.0` or everything `0.1.0`**: rejected in favour of a baseline that reflects each repo's state: `v1.0.0` for modules running on the host with a settled contract, `v0.1.0` for experimental or disabled modules, and continuing from the existing number where a repo already had one that meant something (`spoke-triage` `v0.4.0`, GeneGnome from its `stack.yml` line).
- **Header `Version:` fields as the release version**: rejected. They track single files, and a release touches only some files. They stay as file revisions; `header_template_reference.md` says so.

**Consequences**:
- A repo's first release gets a one-line "Baseline" changelog entry instead of its entire history, unless `release.sh prepare --since REV` names a starting point (`spoke-triage` uses `110fc38`, its last Cargo bump).
- `docs`, `ci`, `chore`, `test`, `style` and `build` commits are left out of changelogs. A change that matters to operators must be typed `feat`, `fix`, `refactor` or `perf`, or marked breaking, for the changelog to show it.
- `sync_modules.sh` checks out a tag `ref` detached, with no pull. It fetches with `--tags` and without `--force`, so if a published tag is moved on the remote, the fetch fails and the sync of that module stops, rather than silently deploying different code under the same version.
- A pinned deployment no longer picks up fixes merged to a module's `main` on the next sync. A fix reaches it only through a release and a `ref` change. That is the intent, and it makes releasing fixes part of the work.
- A release takes two operator steps with a green PR in between, per repo.
- `platform.version` at the top of `modules.yml` is the `modules.yml` schema version, not the hub's release version; it is unchanged by this ADR.

**Revisit When**:
- Release volume makes the two-step manual flow a burden. At that point a GitHub App token would remove the release-please blocker above.
- A second deployment exists. Tag signatures could then be verified at sync time (`git verify-tag`) against a pinned keyring, and a tag ruleset on `v*` could block deleting or moving a published tag.

## ADR-030: Boot Deploy and Safe Shutdown Run as System Units Ordered Against docker.service

**Decision**: `spoke-boot-deploy.service` and `spoke-safe-shutdown.service` are systemd system units that run as the deploying user (`User=`), with `Wants=docker.service` and `After=docker.service`. Boot deploy also orders after `network-online.target` and `local-fs.target` and is `WantedBy=multi-user.target`. `boot_deploy.sh` bounds each Docker readiness probe with `timeout 10 docker info` and measures its wait on wall-clock time. Restart policies on containers are unchanged.

**Context**: Rome rebooted several times on 2026-09-30. Both units were user units under a lingering user manager, with `After=default.target` of that manager, which has no ordering relationship with the system `docker.service`.
- **Shutdown never worked.** On the 09:03, 10:49 and 11:22 shutdowns, `safe_shutdown.sh` ran after Docker had stopped and failed with `dial unix /var/run/docker.sock: connect: no such file or directory` (`make: *** [Makefile:726: stop-all] Error 2`). dockerd stopped the containers itself instead, without the module-then-hub order.
- **Two startup paths competed.** Containers dockerd stops during its own shutdown are not marked as stopped by the operator, so on the next boot dockerd restarts all of them at once according to their restart policies (59 `on-failure`, 7 `unless-stopped`). That boot's journal shows `Loading containers` from 11:23:23 to 11:24:05, with dependents such as portfolio-form-handler logged as `restarting container ... restartPolicy="{on-failure 0}"` because their databases were not up yet. The platform came up with boot deploy disabled, which is how the operator noticed.
- **Boot deploy hung.** It started at 11:23:16, before dockerd had finished loading containers. Its first `docker info` accepted a connection and never returned. The script's `while ! docker info` loop had no timeout, so it stayed in Phase 1 until killed while the hub, which the operator had stopped by hand, stayed down. The same hang explains earlier boots where the unit looked stuck and was SIGTERM'd.

**Rationale**:
- **Ordering needs one systemd manager.** Units stop in reverse start order, but only within one manager. A system unit ordered `After=docker.service` is stopped before `docker.service`, so `ExecStop` has a working daemon. A user unit cannot be ordered against a system unit at all.
- **A clean stop makes boot deploy the single startup authority.** Containers stopped by `docker compose stop` are recorded as stopped, so dockerd does not restore them. After a clean shutdown the only thing that starts services is the ordered, health-gated boot deploy.
- **`Wants=`, not `Requires=` or `BindsTo=`.** With `Requires=`, restarting Docker during a package upgrade would propagate a stop to the shutdown unit and run a full platform stop, and would stop the boot-deploy unit too. Neither is wanted. Boot deploy already polls for Docker itself.
- **Bounded probe.** A hung `docker info` is a transient condition during daemon start-up, and the loop was written to retry transient conditions. `timeout` turns a hang into a failed probe, and wall-clock elapsed time keeps `DOCKER_WAIT` honest when probes are slow.
- **System scope also drops the linger dependency.** The user units only ran because the user manager was lingering.

**Alternatives Considered**:
- **Set every restart policy to `no`**: rejected. dockerd would never restore anything, but a container that crashes during normal operation would also stay down until someone noticed. `on-failure` is the right policy while running; the fix is to make shutdown clean.
- **Disable boot deploy and let dockerd restore everything**: rejected. dockerd starts everything at once with no ordering or health gates, which is what ADR-024's ordering and the postgres-hub crash-recovery handling exist to prevent.
- **Keep user units and add a polling wait in `safe_shutdown.sh`**: rejected. At shutdown the daemon is already gone; waiting cannot bring it back.

**Consequences**:
- Installing needs root: copy both files to `/etc/systemd/system/` with `User=` and the script path filled in, enable them, and remove the user units. The old safe-shutdown user unit must be disabled without `--now`, because stopping it runs its `ExecStop`.
- `systemctl stop` or `restart` of `spoke-safe-shutdown.service` performs a full platform stop, like `make safe-shutdown`. `restart` does not bring the platform back; `make deploy-all` does.
- After an unclean stop (power loss, kernel panic) the shutdown hook did not run, so dockerd restores containers and boot deploy runs too. `docker compose up -d` is idempotent and the two converge; ordering is lost for that one boot only.
- Logs move from `journalctl --user` to the system journal: `journalctl -b -u spoke-boot-deploy` and, for the previous shutdown, `journalctl -b -1 -u spoke-safe-shutdown`.

**Revisit When**:
- A shutdown takes longer than `TimeoutStopSec=600`. systemd would then kill the script and Docker would stop the remainder, still gracefully but unordered.
