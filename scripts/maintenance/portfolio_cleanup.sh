#!/usr/bin/env bash
# ==============================================================================
# SPOKE - PORTFOLIO DATABASE CLEANUP
# ==============================================================================
# Description: Clean up old form submissions from portfolio database
# Author: Matt Barham
# Created: 2026-02-11
# Modified: 2026-04-22
# Version: 2.0.1
# Host: Your Server
# ==============================================================================
# Type: Shell Script (Bash)
# Component: Spoke / maintenance (portfolio cleanup)
# Purpose: Delete form submissions older than 24 hours to keep database clean
# Schedule: Runs daily via systemd timer
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Configuration
POSTGRES_CONTAINER="postgres-hub"
DB_NAME="portfolio"
DB_USER="portfolio_user"
RETENTION_HOURS=24

# Get database password from secret
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOKE_DIR="${SPOKE_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
PASSWORD_FILE="${SPOKE_DIR}/secrets/portfolio/portfolio_db_password"

if [[ ! -f "${PASSWORD_FILE}" ]]; then
    printf "ERROR: Password file not found: %s\n" "${PASSWORD_FILE}" >&2
    exit 1
fi

DB_PASSWORD=$(cat "${PASSWORD_FILE}")

# Execute cleanup query
printf "Cleaning up portfolio form submissions older than %d hours...\n" "${RETENTION_HOURS}"

DELETED_COUNT=$(docker exec -e PGPASSWORD="${DB_PASSWORD}" "${POSTGRES_CONTAINER}" \
    psql -U "${DB_USER}" -d "${DB_NAME}" -t -c \
    "DELETE FROM form_submissions WHERE submitted_at < NOW() - INTERVAL '${RETENTION_HOURS} hours'; SELECT ROW_COUNT();" \
    2>&1 | grep -oP '^\s*\K\d+' || echo "0")

if [[ "${DELETED_COUNT}" =~ ^[0-9]+$ ]]; then
    printf "Cleanup complete: %d old submissions removed\n" "${DELETED_COUNT}"
    exit 0
else
    printf "Cleanup completed but could not determine row count\n"
    exit 0
fi
