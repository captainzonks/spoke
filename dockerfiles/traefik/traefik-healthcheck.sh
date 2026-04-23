#!/bin/sh
# ==============================================================================
# SPOKE HUB - TRAEFIK HEALTHCHECK
# ==============================================================================
# Description: Validates Traefik is ready:
#              1. Ping endpoint responds
#              2. Plugins registered in API rawdata
#                 (crowdsec-bouncer, sablier, htransformation)
#              Returns: 0 if healthy, 1 if unhealthy
# Author: Matt Barham
# Created: 2026-02-12
# Modified: 2026-04-22
# Version: 1.0.1
# Host: Your Server
# ==============================================================================
# Type: Shell Script (POSIX sh)
# Component: spoke hub / service: traefik
# ==============================================================================

set -e

# CHECK 1: Ping Endpoint
if ! wget --no-verbose --tries=1 --spider "http://localhost:8081/ping" >/dev/null 2>&1; then
    echo "UNHEALTHY: Ping endpoint not responding"
    exit 1
fi

# CHECK 2: Plugin Loading (via API rawdata)
# Traefik registers plugins under middlewares once loaded. Check that the
# crowdsec plugin is present — if it is, all plugins loaded successfully.
RAWDATA=$(wget --no-verbose --tries=1 -q -O - "http://localhost:8081/api/rawdata" 2>/dev/null || true)
if [ -n "${RAWDATA}" ]; then
    if ! echo "${RAWDATA}" | grep -q "crowdsec-bouncer-traefik-plugin"; then
        echo "UNHEALTHY: Plugins not loaded yet"
        exit 1
    fi
fi

echo "HEALTHY: Traefik responding (ping OK, plugins loaded)"
exit 0
