#!/bin/sh
# ==============================================================================
# SPOKE HUB - REDIS ENTRYPOINT
# ==============================================================================
# Description: Reads redis_password secret and passes requirepass to redis-server
# Author: Matt Barham
# Created: 2026-04-06
# Modified: 2026-04-22
# Version: 1.0.1
# Host: Your Server
# ==============================================================================
# Type: Shell Script (POSIX sh)
# Component: spoke hub / service: redis
# ==============================================================================

set -e

if [ -f "/run/secrets/redis_password" ]; then
    REDIS_PASSWORD="$(cat /run/secrets/redis_password)"
    exec redis-server "$@" --requirepass "${REDIS_PASSWORD}"
else
    echo "WARN: /run/secrets/redis_password not found — starting without password"
    exec redis-server "$@"
fi
