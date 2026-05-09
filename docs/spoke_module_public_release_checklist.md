# Spoke Module — Public Release Checklist

<!--
==============================================================================
spoke_module_public_release_checklist.md
==============================================================================
Description: Recipe for promoting a Rome-deployed Spoke module to a public,
             standalone GitHub repository in the captainzonks/spoke-* family.
Author: Matt Barham
Created: 2026-05-08
Version: 1.0.0
==============================================================================
Document Type: Checklist + Reference
Audience: Module Developer (Matt) preparing a module for open-source release
Status: Active
==============================================================================
-->

## When to Use

Apply this when an internal Rome-deployed module is going public. The module
already works in Rome and you want to publish it under
`captainzonks/spoke-<name>` so other Spoke users can install it.

The first public release of `spoke-backup` (2026-05-08) is the canonical
worked example for every step here.

## Goals

A public Spoke module must be:

1. **Standalone** — works without assuming any other specific Spoke module is deployed.
2. **Generic** — no host-specific identifiers (cluster names, internal IPs, paths, hostnames, email addresses).
3. **Configurable** — site-specific behavior driven by env vars or bind-mounted config files.
4. **Documented** — README + docs/ explain Secrets, Sources, First-time Setup, Restore.
5. **Clean history** — single squashed initial commit, no leaked context from internal iteration.

## Checklist

### 1. Make the module standalone

Walk every script, compose file, env example, and Traefik rule. Replace
hardcoded site-specific values with one of three patterns:

| Pattern | Use for | Example |
|---------|---------|---------|
| **Env var (space-separated tuples)** | Lists of things (clusters, sources) | `BACKUP_PG_CLUSTERS="hub:postgres-hub immich:immich-postgres"` |
| **Env var (single value)** | Toggleable paths/flags | `BACKUP_NOTIFY_TO=admin@example.com` |
| **Bind-mounted config file** | Long lists or structured data (excludes, allowlists) | `/etc/backup/appdata-excludes.conf` |

Anti-patterns to remove:

- Hardcoded loops over named items (`dump_cluster hub ... ; dump_cluster immich ...`).
- Hardcoded host paths in compose volumes (e.g. site-specific `${IMMICH_UPLOAD_DIR}`).
- Hardcoded service-specific exclusion paths inside policy/setup scripts.
- Compose secrets that only exist on your host (`postgres_immich_backup_password`, `postgres_genetics_backup_password`, etc.).

When you remove these from the public compose file, replace them with **a comment that explains how to add them back via `docker-compose.override.yml`** so a Spoke deployer can extend the module without forking.

### 2. Bash gotcha: IFS + `read -ra`

When refactoring a hardcoded list into a data-driven loop, you'll likely write something like:

```bash
for pair in ${BACKUP_PG_CLUSTERS}; do ...
```

Or:

```bash
read -ra clusters <<< "$BACKUP_PG_CLUSTERS"
```

**Both are silent bugs** if the script also has `IFS=$'\n\t'` (which it should, for safety). Use a command-scoped IFS prefix:

```bash
IFS=' ' read -ra clusters <<< "$BACKUP_PG_CLUSTERS"
for pair in "${clusters[@]}"; do ...
```

See `~/.claude/skills/learned/bash-ifs-read-ra-space-split.md` for the deeper write-up.

### 3. Rome side — restore site-specific behavior

What you removed from the public compose, you re-add on the Rome side as **gitignored** files next to the module:

- `Rome/modules/<name>/docker-compose.override.yml` — adds the site-specific volumes, declares extra secrets, bind-mounts site config files
- `Rome/modules/<name>/<config>.conf` — site-specific config (e.g. `appdata-excludes.conf`)
- `Rome/modules.yml` `env_overrides` — site-specific env values (cluster lists, paths, IPs, email addresses)

Verify the override file path is gitignored at the module-repo level. The site-config files (e.g. `appdata-excludes.conf`) should also be gitignored in the public module.

### 4. Traefik rule template

Spoke routes use a hybrid templating model:

| Variable | Where it lives | How it's resolved |
|----------|----------------|-------------------|
| `${KOPIA_SUBDOMAIN}` (module-specific) | Module `.env` | **Deploy time** via `deploy_traefik_rules.sh` envsubst |
| `{{ env "DOMAIN" }}` (hub-level) | Traefik container env | **Runtime** by Traefik Go template |

Do NOT use `{{ env "MODULE_VAR" }}` — Traefik does not have module-specific
vars in its environment. The Go template renders to empty string and the
host rule never matches.

```yaml
# WRONG — Traefik does not have KOPIA_SUBDOMAIN
rule: Host(`{{ env "KOPIA_SUBDOMAIN" }}.{{ env "DOMAIN" }}`)

# RIGHT — KOPIA_SUBDOMAIN substituted at deploy time
rule: Host(`${KOPIA_SUBDOMAIN}.{{ env "DOMAIN" }}`)
```

### 5. Auth chain choice

If the service has its **own auth** (basic auth, native OIDC, internal user accounts), put it on `chain-no-auth@file`, NOT `chain-admin-strict@file`. Stacking Authentik forward-auth in front of a service that also wants basic auth produces an unrecoverable loop where the browser's basic-auth header is overwritten by Authentik's.

See `~/.claude/skills/learned/authentik-forward-auth-blocks-basic-auth.md`.

### 6. Documentation

Required files in the public repo:

- `README.md` — Features, Architecture diagram, Networks, Secrets, Environment Variables (link to `.env.example`), First-time Setup, Backup Sources, Restore link, License
- `.env.example` — every variable with comments, generic placeholder values
- `docs/restore.md` (or equivalent) — disaster-recovery runbook
- `docs/sources.md` (if applicable) — what's backed up / what's optional
- `LICENSE` — MIT (Spoke convention)
- `stack.yml` — Spoke module manifest

The README must say "this module is **standalone**" and explain the
extension hooks (override.yml, env vars).

### 7. Sensitive-info scrub

Before pushing anything public, grep history and working tree for site-specific markers:

```bash
rg -niE '(rome|barhamm|zonks\.org|dionysus|matthew\.barham|<your-internal-host>|192\.168\.3[45]|<your-cluster-names>)' .
git log -p --all | grep -iE '(<same patterns>)'
```

What's OK to leave:

- Author identity (your name + email in commits).
- **Spoke platform default subnets** (`192.168.34.0/24` for `db_backup`, `192.168.35.0/24` for `troxy`) — these are documented Spoke conventions used by every module.

What MUST be removed:

- Site-specific cluster/host names (e.g. `postgres18-genetics`, `immich-postgres` IF that's not a Spoke convention but your own naming).
- Site-specific hostnames (`rome`, custom domain).
- Site-specific email addresses.
- Real B2 bucket names (use `example-backup-v1` style placeholders).
- Real internal IPs beyond the Spoke defaults.

### 8. History scrub (squash to single commit)

Once the working tree is clean, rewrite history to a single root commit so
you don't ship the embarrassing evolution from "Rome-specific" to "generic":

```bash
git checkout --orphan public-release
git commit -m "feat: initial spoke-<name> module"
git branch -D main
git branch -m main
```

Then force-push:

```bash
gh api -X PUT repos/captainzonks/spoke-<name>/rulesets/<id> -f enforcement=disabled
git push origin main --force-with-lease
gh api -X PUT repos/captainzonks/spoke-<name>/rulesets/<id> -f enforcement=active
```

If branch protection blocks the push, get the ruleset ID with
`gh api repos/captainzonks/spoke-<name>/rulesets`. Re-arm the ruleset
**immediately** after the push.

Delete any stale feature branches on origin in the same operation.

### 9. Validate end-to-end on Rome before flipping public

In `Rome/modules/<name>/`:

```bash
git fetch origin
git reset --hard origin/main      # Pull squashed orphan
make rebuild MODULE=<name> NO_CACHE=true FORCE_REGEN=true
```

Trigger the module's primary workflow (e.g. `docker exec backup-orchestrator /usr/local/bin/backup.sh --once`). Verify everything runs to completion, including:

- Site-specific extensions still work (volumes from override.yml).
- Site-specific config still applies (excludes, cluster lists).
- No regressions vs the pre-genericized version.

Fix any issues. Push fix as a normal PR (not orphan amend) — once the public repo is alive, treat history as immutable.

### 10. Flip visibility

```bash
gh api -X PATCH repos/captainzonks/spoke-<name> -F private=false
```

### 11. Update profile README

Add a row to the modules table in `captainzonks/captainzonks/README.md`. Single PR or commit-to-main; small change.

### 12. Post-release housekeeping

- If the squash deleted any kopia/orphan snapshots that referenced old paths, prune them: `kopia snapshot delete <id> --delete && kopia maintenance run --safety=full`.
- Confirm cron schedule still fires next day.
- Delete merged feature branches locally and on remote.

## Lessons captured as skills

- [bash-ifs-read-ra-space-split](../../.claude/skills/learned/bash-ifs-read-ra-space-split.md) — defensive IFS breaks intentional space-split
- [authentik-forward-auth-blocks-basic-auth](../../.claude/skills/learned/authentik-forward-auth-blocks-basic-auth.md) — stacked auth layers create unrecoverable browser dialog loop
- [spoke-traefik-rule-envsubst-pattern](../../.claude/skills/learned/spoke-traefik-rule-envsubst-pattern.md) — `${VAR}` for module vars, `{{ env "VAR" }}` for hub vars

## Worked example

`spoke-backup` released 2026-05-08. Repo:
[github.com/captainzonks/spoke-backup](https://github.com/captainzonks/spoke-backup).
Profile entry in
[github.com/captainzonks](https://github.com/captainzonks).
