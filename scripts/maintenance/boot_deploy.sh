#!/usr/bin/env bash
# ==============================================================================
# BOOT_DEPLOY.SH
# ==============================================================================
# Description: Ordered Spoke deployment on cold boot
# Author: Matt Barham
# Created: 2026-03-11
# Modified: 2026-03-23
# Version: 2.0.0
# ==============================================================================
# Purpose: Wait for Docker daemon readiness, deploy hub services, wait for
#          critical hub health, then deploy modules. Designed to run as a
#          systemd user service on boot.
#
# Boot timeline:
#   1. Wait for Docker daemon
#   2. Deploy hub (docker compose up -d)
#   3. Wait for postgres-hub healthy (WAL recovery can take minutes)
#   4. Wait for crowdsec healthy (depends on postgres)
#   5. Wait for traefik healthy (depends on crowdsec)
#   6. Deploy all enabled modules
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOKE_DIR="${SPOKE_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
DOCKER_WAIT=120
HUB_HEALTH_WAIT=600
POLL_INTERVAL=5
LOG_TAG="spoke-boot-deploy"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Wait for a container to report healthy
# Usage: wait_healthy <container_name> <max_wait_seconds>
wait_healthy() {
    local container="$1"
    local max_wait="$2"
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        local status
        status="$(docker inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null || echo 'missing')"

        case "$status" in
            healthy)
                log "  ${container}: healthy (${elapsed}s)"
                return 0
                ;;
            unhealthy)
                log "  ${container}: unhealthy after ${elapsed}s"
                return 1
                ;;
            missing)
                log "  ${container}: not found, waiting... (${elapsed}s/${max_wait}s)"
                ;;
            *)
                log "  ${container}: ${status} (${elapsed}s/${max_wait}s)"
                ;;
        esac

        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    log "  ${container}: timed out after ${max_wait}s"
    return 1
}

log "Spoke boot deploy starting (SPOKE_DIR=${SPOKE_DIR})"

# ==============================================================================
# PHASE 1: Wait for Docker daemon
# ==============================================================================
elapsed=0
while ! docker info >/dev/null 2>&1; do
    if [[ $elapsed -ge $DOCKER_WAIT ]]; then
        log "ERROR: Docker daemon not ready after ${DOCKER_WAIT}s"
        exit 1
    fi
    log "Waiting for Docker daemon... (${elapsed}s/${DOCKER_WAIT}s)"
    sleep $POLL_INTERVAL
    elapsed=$((elapsed + POLL_INTERVAL))
done
log "Docker daemon ready after ${elapsed}s"

# ==============================================================================
# PHASE 2: Deploy hub services
# ==============================================================================
# Compose's depends_on: service_healthy gate can time out when authentik takes
# longer than its start_period on cold boot (postgres WAL recovery + django
# migrations). Retry a few times, then fall through — Phase 3 does the
# authoritative health validation with restart logic.
log "Deploying hub services..."
cd "${SPOKE_DIR}"
hub_deploy_attempt=1
hub_deploy_max=3
while true; do
    if make hub-deploy 2>&1; then
        break
    fi
    if [[ $hub_deploy_attempt -ge $hub_deploy_max ]]; then
        log "WARNING: hub-deploy failed ${hub_deploy_attempt}× — continuing to Phase 3 health validation"
        break
    fi
    log "WARNING: hub-deploy failed (attempt ${hub_deploy_attempt}/${hub_deploy_max}) — retrying in 30s"
    sleep 30
    hub_deploy_attempt=$((hub_deploy_attempt + 1))
done
log "Hub compose up complete — waiting for critical services..."

# ==============================================================================
# PHASE 3: Wait for critical hub services to be healthy
# ==============================================================================
# Order matters: postgres must be healthy before crowdsec can start,
# crowdsec must be healthy before traefik can start (when CROWDSEC_ENABLED).
hub_healthy=true

log "Waiting for postgres-hub..."
if ! wait_healthy "postgres-hub" "$HUB_HEALTH_WAIT"; then
    log "ERROR: postgres-hub failed health check — attempting restart"
    docker restart postgres-hub
    if ! wait_healthy "postgres-hub" 120; then
        log "ERROR: postgres-hub still unhealthy after restart"
        hub_healthy=false
    fi
fi

# Check if CrowdSec is enabled (container exists and is not a profile-only service)
if docker inspect crowdsec >/dev/null 2>&1; then
    log "Waiting for crowdsec..."
    if ! wait_healthy "crowdsec" 300; then
        log "WARNING: crowdsec failed health check — attempting restart"
        docker restart crowdsec
        if ! wait_healthy "crowdsec" 120; then
            log "WARNING: crowdsec still unhealthy after restart"
        fi
    fi
fi

log "Waiting for traefik..."
if ! wait_healthy "traefik" 300; then
    log "WARNING: traefik failed health check — attempting restart"
    docker restart traefik
    if ! wait_healthy "traefik" 120; then
        log "ERROR: traefik still unhealthy after restart"
        hub_healthy=false
    fi
fi

# Also wait for redis (needed by authentik and some modules)
log "Waiting for redis..."
if ! wait_healthy "redis" 60; then
    log "WARNING: redis not healthy"
fi

# Authentik (forward-auth gate for modules). Slow on cold boot due to django
# migrations. Non-fatal — modules will deploy and work; only SSO-protected
# routes will fail until authentik recovers.
if docker inspect authentik >/dev/null 2>&1; then
    log "Waiting for authentik..."
    if ! wait_healthy "authentik" 300; then
        log "WARNING: authentik failed health check — attempting restart"
        docker restart authentik
        if ! wait_healthy "authentik" 180; then
            log "WARNING: authentik still unhealthy — SSO-gated routes will fail until recovered"
        fi
    fi
fi

if [[ "$hub_healthy" != "true" ]]; then
    log "ERROR: Critical hub services not healthy — aborting module deployment"
    log "Run 'make hub-health' to diagnose, then 'make deploy-all' to retry"
    exit 1
fi

log "All critical hub services healthy"

# ==============================================================================
# PHASE 4: Deploy all enabled modules
# ==============================================================================
log "Deploying all enabled modules..."
if command -v yq &>/dev/null && [ -f "${SPOKE_DIR}/modules.yml" ]; then
    for module in $(yq -r '.modules | to_entries[] | select(.value.enabled == true) | .key' "${SPOKE_DIR}/modules.yml"); do
        if [ -d "${SPOKE_DIR}/modules/${module}" ]; then
            log "Deploying module: ${module}"
            make deploy MODULE="$module" 2>&1 || log "WARNING: module ${module} deploy failed"
        else
            log "Skipping ${module} (not synced)"
        fi
    done
else
    log "WARNING: yq not available or modules.yml missing — deploying available modules"
    for module_dir in "${SPOKE_DIR}"/modules/*/; do
        module="$(basename "$module_dir")"
        log "Deploying module: ${module}"
        make deploy MODULE="$module" 2>&1 || log "WARNING: module ${module} deploy failed"
    done
fi

log "Spoke boot deploy completed successfully"
exit 0
