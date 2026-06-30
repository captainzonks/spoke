#!/usr/bin/env bash
# ==============================================================================
# SPOKE - SAFE SHUTDOWN
# ==============================================================================
# Description: Graceful ordered stop of all Spoke services for reboot/shutdown
# Author: Matt Barham (with Claude Code assistance)
# Created: 2026-06-30
# Modified: 2026-06-30
# Version: 1.0.0
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
# Note: For OS reboot/poweroff, Docker's daemon already stops containers
#       gracefully honoring stop_grace_period, so this script is primarily for
#       MANUAL graceful shutdown (e.g. before maintenance) or as a systemd
#       ExecStop hook. It is safe to run repeatedly (idempotent).
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

log "Spoke safe shutdown complete"
exit 0
