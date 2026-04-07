#!/bin/sh
# ==============================================================================
# REDIS ENTRYPOINT - Secret-aware wrapper
# ==============================================================================
# Description: Reads redis_password secret and passes requirepass to redis-server
# Author: Matt Barham
# Created: 2026-04-06
# Modified: 2026-04-06
# Version: 1.0.0
# ==============================================================================

set -e

if [ -f "/run/secrets/redis_password" ]; then
    REDIS_PASSWORD="$(cat /run/secrets/redis_password)"
    exec redis-server "$@" --requirepass "${REDIS_PASSWORD}"
else
    echo "WARN: /run/secrets/redis_password not found — starting without password"
    exec redis-server "$@"
fi
