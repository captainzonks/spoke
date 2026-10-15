#!/usr/bin/env bash
# ==============================================================================
# SPOKE - SAFE SHUTDOWN
# ==============================================================================
# Description: Graceful ordered stop of all Spoke services for reboot/shutdown
# Author: Matt Barham (with Claude Code assistance)
# Created: 2026-06-30
# Modified: 2026-10-15
# Version: 1.2.0
# Host: Your Server
# ==============================================================================
# Type: Shell Script (Bash)
# Component: Spoke / maintenance (shutdown orchestrator)
# ==============================================================================
# Purpose: Stop modules first, then hub, letting Docker honor each service's
#          stop_grace_period so stateful services (postgres-hub, redis,
#          crowdsec) checkpoint/flush cleanly instead of being SIGKILLed.
#          A clean stop avoids PostgreSQL crash recovery (full data-dir fsync +
#          WAL replay) on the next boot.
#
# Note: Runs on every reboot/poweroff as the ExecStop of the
#       spoke-safe-shutdown system unit, which is ordered After=docker.service
#       so this script runs before the Docker daemon stops (ADR-030). A stop
#       done here also marks containers as stopped, so dockerd does not
#       auto-restart them at the next boot. Also usable manually
#       (`make safe-shutdown`). Safe to run repeatedly (idempotent).
#
# Post-stop hooks: after everything is stopped, every executable file in
#       ${SPOKE_DIR}/scripts/local/shutdown_post.d/ runs in name order (site
#       scripts, e.g. cycle a UPS output). A hook may start a container again
#       for one last command. Hooks are bounded by HOOK_TIMEOUT and a failing
#       hook is logged, never fatal. The directory is optional and gitignored
#       with the rest of scripts/local/.
#
# Usage:
#   ./safe_shutdown.sh            # Stop all modules, then hub
#   make safe-shutdown            # Same, via Makefile
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOKE_DIR="${SPOKE_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
PG_STOP_TIMEOUT=90
HOOK_DIR="${SPOKE_DIR}/scripts/local/shutdown_post.d"
HOOK_TIMEOUT=60
LOG_TAG="spoke-safe-shutdown"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log "Spoke safe shutdown starting (SPOKE_DIR=${SPOKE_DIR})"
cd "${SPOKE_DIR}"

# ==============================================================================
# PHASE 1: Stop all modules, then hub (correct dependency order)
# ==============================================================================
# 'make stop-all' stops every module first, then the hub. 'docker compose stop'
# honors each service's stop_grace_period, giving stateful services a clean
# shutdown window.
if ! make stop-all 2>&1; then
    log "WARNING: 'make stop-all' reported errors — verifying critical DB stop below"
fi

# ==============================================================================
# PHASE 2: Guarantee postgres-hub stopped cleanly (defense in depth)
# ==============================================================================
# Independent of compose grace settings, make sure the database is given a long
# grace window so it is never SIGKILLed mid-checkpoint.
if docker inspect postgres-hub >/dev/null 2>&1; then
    running="$(docker inspect -f '{{.State.Running}}' postgres-hub 2>/dev/null || echo false)"
    if [[ "$running" == "true" ]]; then
        log "postgres-hub still running — stopping with ${PG_STOP_TIMEOUT}s grace"
        if docker stop -t "$PG_STOP_TIMEOUT" postgres-hub >/dev/null 2>&1; then
            log "postgres-hub stopped cleanly"
        else
            log "WARNING: postgres-hub stop returned an error — check 'docker logs postgres-hub'"
        fi
    else
        log "postgres-hub already stopped"
    fi
fi

# ==============================================================================
# PHASE 3: Site post-stop hooks (optional)
# ==============================================================================
if [[ -d "$HOOK_DIR" ]]; then
    for hook in "$HOOK_DIR"/*; do
        [[ -f "$hook" && -x "$hook" ]] || continue
        log "running post-stop hook: $(basename "$hook")"
        if timeout -k 5 "$HOOK_TIMEOUT" "$hook" 2>&1; then
            log "hook finished: $(basename "$hook")"
        else
            log "WARNING: hook failed or timed out (${HOOK_TIMEOUT}s): $(basename "$hook")"
        fi
    done
fi

log "Spoke safe shutdown complete"
exit 0
