#!/usr/bin/env bash
# ==============================================================================
# SPOKE - DUCKDNS DYNAMIC DNS UPDATER
# ==============================================================================
# Description: Update DuckDNS DDNS record with current public IP
# Author: Matt Barham
# Created: 2026-03-16
# Modified: 2026-04-22
# Version: 1.0.1
# Host: Your Server
# ==============================================================================
# Type: Shell Script (Bash)
# Component: Spoke / maintenance (DDNS)
# ==============================================================================
# Purpose: Reliable DDNS updates for residential IPs using DuckDNS. Reads
#          credentials from Spoke secrets, validates responses, and retries
#          on transient failures (DNS resolution, API timeouts).
#
# Setup:
#   1. Create secret file: secrets/duckdns/duckdns_token
#   2. Add DUCKDNS_DOMAIN to shared/env/base.env (your subdomain name only)
#   3. Install systemd units:
#        sudo cp update_duckdns.service update_duckdns.timer /etc/systemd/system/
#        sudo systemctl daemon-reload
#        sudo systemctl enable --now update_duckdns.timer
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOKE_DIR="${SPOKE_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
DUCKDNS_API="https://www.duckdns.org/update"
MAX_RETRIES=3
RETRY_DELAY=10

# Load environment variables (base.env defines DUCKDNS_DOMAIN)
BASE_ENV_FILE="${SPOKE_DIR}/shared/env/base.env"
if [[ -f "${BASE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${BASE_ENV_FILE}"
else
    printf "ERROR: Environment file not found: %s\n" "${BASE_ENV_FILE}" >&2
    exit 1
fi

# Validate required environment variable
: "${DUCKDNS_DOMAIN:?ERROR: DUCKDNS_DOMAIN not set in base.env}"

# Load token from secrets
TOKEN_FILE="${SPOKE_DIR}/secrets/duckdns/duckdns_token"
if [[ -f "${TOKEN_FILE}" ]]; then
    DUCKDNS_TOKEN="$(cat "${TOKEN_FILE}")"
    if [[ -z "${DUCKDNS_TOKEN}" ]]; then
        printf "ERROR: Token file is empty: %s\n" "${TOKEN_FILE}" >&2
        exit 1
    fi
else
    printf "ERROR: Token file not found: %s\n" "${TOKEN_FILE}" >&2
    printf "Create it with: mkdir -p %s/secrets/duckdns && echo 'your-token' > %s\n" \
        "${SPOKE_DIR}" "${TOKEN_FILE}" >&2
    exit 1
fi

# Update DuckDNS with retry logic
update_duckdns() {
    local attempt=1
    local response

    while [[ ${attempt} -le ${MAX_RETRIES} ]]; do
        response=$(curl \
            --silent \
            --show-error \
            --max-time 30 \
            --retry 0 \
            "${DUCKDNS_API}?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=" \
            2>&1) || {
            printf "WARN: curl failed (attempt %d/%d): %s\n" \
                "${attempt}" "${MAX_RETRIES}" "${response}" >&2
            attempt=$((attempt + 1))
            if [[ ${attempt} -le ${MAX_RETRIES} ]]; then
                printf "Retrying in %ds...\n" "${RETRY_DELAY}" >&2
                sleep "${RETRY_DELAY}"
            fi
            continue
        }

        # DuckDNS returns "OK" on success, "KO" on failure
        if [[ "${response}" == "OK" ]]; then
            printf "DuckDNS updated successfully for %s.duckdns.org\n" "${DUCKDNS_DOMAIN}"
            return 0
        elif [[ "${response}" == "KO" ]]; then
            printf "ERROR: DuckDNS returned KO — check domain name and token\n" >&2
            return 1
        else
            printf "WARN: Unexpected response (attempt %d/%d): %s\n" \
                "${attempt}" "${MAX_RETRIES}" "${response}" >&2
            attempt=$((attempt + 1))
            if [[ ${attempt} -le ${MAX_RETRIES} ]]; then
                printf "Retrying in %ds...\n" "${RETRY_DELAY}" >&2
                sleep "${RETRY_DELAY}"
            fi
        fi
    done

    printf "ERROR: Failed after %d attempts\n" "${MAX_RETRIES}" >&2
    return 1
}

update_duckdns
