#!/bin/sh
set -e

# ============================================================================
# TRAEFIK READINESS CHECKS
# ============================================================================
# Validates dependencies before starting Traefik to prevent plugin failures
# ============================================================================

echo "========================================"
echo "TRAEFIK READINESS CHECKS"
echo "========================================"

MAX_WAIT=120
WAIT_INTERVAL=5

# ============================================================================
# CHECK 1: External Network Connectivity (for plugin downloads)
# ============================================================================
echo "[1/3] Checking external network connectivity..."

PLUGIN_HOST="plugins.traefik.io"
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    if curl -s --connect-timeout 5 --max-time 10 "https://${PLUGIN_HOST}" > /dev/null 2>&1; then
        echo "  OK: Network is ready (reached ${PLUGIN_HOST})"
        break
    fi

    echo "  Waiting for network connectivity to ${PLUGIN_HOST}... (${ELAPSED}s/${MAX_WAIT}s)"
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "  WARN: Network readiness check timed out after ${MAX_WAIT}s"
    echo "  Proceeding anyway - Traefik will retry plugin downloads"
fi

# ============================================================================
# CHECK 2: Docker Socket Proxy Availability
# ============================================================================
echo "[2/3] Checking Docker socket-proxy connectivity..."

ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    if nc -z -w 5 socket-proxy 2375 2>/dev/null; then
        echo "  OK: Socket-proxy is reachable"
        break
    fi

    echo "  Waiting for socket-proxy... (${ELAPSED}s/${MAX_WAIT}s)"
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "  WARN: Socket-proxy readiness check timed out after ${MAX_WAIT}s"
    echo "  Docker provider may fail to initialize properly"
fi

# ============================================================================
# CHECK 3: CrowdSec API Availability (for bouncer plugin)
# ============================================================================
if [ "${CROWDSEC_ENABLED:-true}" = "true" ]; then
    echo "[3/3] Checking CrowdSec LAPI health endpoint..."

    CROWDSEC_HEALTH="http://crowdsec:8080/health"
    ELAPSED=0

    while [ $ELAPSED -lt $MAX_WAIT ]; do
        if curl -s --connect-timeout 5 --max-time 10 "${CROWDSEC_HEALTH}" > /dev/null 2>&1; then
            echo "  OK: CrowdSec LAPI health endpoint is ready"
            break
        fi

        echo "  Waiting for CrowdSec LAPI health... (${ELAPSED}s/${MAX_WAIT}s)"
        sleep $WAIT_INTERVAL
        ELAPSED=$((ELAPSED + WAIT_INTERVAL))
    done

    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "  ERROR: CrowdSec LAPI not ready after ${MAX_WAIT}s"
        echo "  This will cause plugin loading failures - refusing to start"
        exit 1
    fi
else
    echo "[3/3] CROWDSEC_ENABLED=false — skipping CrowdSec readiness check"
fi

echo "========================================"
echo "All readiness checks complete"
echo "========================================"

# ============================================================================
# SECRETS LOADING
# ============================================================================
# Load secrets from /run/secrets/ into environment variables

if [ -f "/run/secrets/crowdsec_lapi_key" ]; then
  CROWDSEC_LAPI_KEY="$(cat /run/secrets/crowdsec_lapi_key)"
  export CROWDSEC_LAPI_KEY
fi

if [ -f "/run/secrets/crowdsec_online_api_login" ]; then
  CROWDSEC_CAPI_LOGIN="$(cat /run/secrets/crowdsec_online_api_login)"
  export CROWDSEC_CAPI_LOGIN
fi

if [ -f "/run/secrets/crowdsec_online_api_password" ]; then
  CROWDSEC_CAPI_PASSWORD="$(cat /run/secrets/crowdsec_online_api_password)"
  export CROWDSEC_CAPI_PASSWORD
fi

if [ -f "/run/secrets/redis_password" ]; then
  REDIS_PASSWORD="$(cat /run/secrets/redis_password)"
  export REDIS_PASSWORD
  set -- "$@" "--providers.redis.password=${REDIS_PASSWORD}"
fi

if [ -f "/run/secrets/basic_auth_credentials" ]; then
  HTPASSWD_FILE="/run/secrets/basic_auth_credentials"
  export HTPASSWD_FILE
fi

if [ -f "/run/secrets/agent_htpasswd_credentials" ]; then
  AGENT_HTPASSWD_FILE="/run/secrets/agent_htpasswd_credentials"
  export AGENT_HTPASSWD_FILE
fi

# Execute the Traefik binary
exec /entrypoint.sh "$@"
