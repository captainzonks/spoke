#!/usr/bin/env bash
# ==============================================================================
# BOOT_DEPLOY.SH
# ==============================================================================
# Description: Ordered Spoke deployment on cold boot
# Author: Matt Barham
# Created: 2026-03-11
# Modified: 2026-03-11
# Version: 1.0.0
# ==============================================================================
# Purpose: Wait for Docker daemon readiness, then deploy hub and all modules
#          in dependency order via 'make deploy-all'. Designed to run as a
#          systemd user service on boot (replaces implicit container restart).
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOKE_DIR="${SPOKE_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
MAX_WAIT=120
POLL_INTERVAL=5
LOG_TAG="spoke-boot-deploy"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log "Spoke boot deploy starting (SPOKE_DIR=${SPOKE_DIR})"

# Wait for Docker daemon
elapsed=0
while ! docker info >/dev/null 2>&1; do
    if [[ $elapsed -ge $MAX_WAIT ]]; then
        log "ERROR: Docker daemon not ready after ${MAX_WAIT}s"
        exit 1
    fi
    log "Waiting for Docker daemon... (${elapsed}s/${MAX_WAIT}s)"
    sleep $POLL_INTERVAL
    elapsed=$((elapsed + POLL_INTERVAL))
done

log "Docker daemon ready after ${elapsed}s"

# Wait for Docker networks (they may take a moment after daemon start)
net_elapsed=0
while ! docker network inspect troxy >/dev/null 2>&1; do
    if [[ $net_elapsed -ge 30 ]]; then
        log "WARNING: troxy network not found after 30s, proceeding anyway"
        break
    fi
    sleep 2
    net_elapsed=$((net_elapsed + 2))
done

log "Starting ordered deployment via 'make deploy-all'"
cd "${SPOKE_DIR}"
make deploy-all 2>&1

exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    log "Spoke boot deploy completed successfully"
else
    log "ERROR: Spoke boot deploy failed with exit code ${exit_code}"
fi

exit $exit_code
