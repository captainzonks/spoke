#!/bin/sh
# ============================================================================
# TRAEFIK HEALTHCHECK
# ============================================================================
# Validates Traefik is ready:
#   1. Ping endpoint responds
#   2. Plugins successfully loaded
# Returns: 0 if healthy, 1 if unhealthy
# ============================================================================

set -e

# CHECK 1: Ping Endpoint
if ! wget --no-verbose --tries=1 --spider "http://localhost:8081/ping" >/dev/null 2>&1; then
    echo "UNHEALTHY: Ping endpoint not responding"
    exit 1
fi

# CHECK 2: Plugin Loading (via log check)
if [ -f /proc/1/fd/1 ]; then
    if ! grep -q "Plugins loaded" /proc/1/fd/1 2>/dev/null; then
        echo "UNHEALTHY: Plugins not loaded yet"
        exit 1
    fi
fi

echo "HEALTHY: Traefik responding (ping OK, plugins loaded)"
exit 0
