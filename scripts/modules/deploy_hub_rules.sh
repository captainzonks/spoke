#!/usr/bin/env bash
# ==============================================================================
# SPOKE - DEPLOY HUB RULES
# ==============================================================================
# Description: Copies hub/traefik/rules/ to appdata/traefik/rules/ with hub_ prefix
# Author: Matt Barham
# Created: 2026-02-12
# Modified: 2026-04-22
# Version: 1.0.1
# Host: Your Server
# ==============================================================================
# Type: Shell Script (Bash)
# Component: Spoke hub / traefik rules deployer
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

SPOKE_DIR="${SPOKE_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
HUB_RULES_DIR="${SPOKE_DIR}/hub/traefik/rules"
RULES_DIR="${SPOKE_DIR}/appdata/traefik/rules"
PLUGINS_DIR="${SPOKE_DIR}/appdata/traefik/plugins-storage"
CROWDSEC_ENABLED="${CROWDSEC_ENABLED:-true}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "${RULES_DIR}"

# Ensure plugins-storage exists with correct ownership
mkdir -p "${PLUGINS_DIR}"
if [ "$(stat -c '%u' "${PLUGINS_DIR}")" = "0" ]; then
    printf "${RED}  WARNING: %s is owned by root${NC}\n" "${PLUGINS_DIR}"
    printf "${RED}  Traefik runs as non-root and cannot write plugins here${NC}\n"
    printf "${RED}  Run: sudo chown -R \$(id -u):\$(id -g) %s${NC}\n" "${PLUGINS_DIR}"
fi

if [ "${CROWDSEC_ENABLED}" = "false" ]; then
    printf "${YELLOW}  CROWDSEC_ENABLED=false — deploying no-CrowdSec middleware variant${NC}\n"
fi

rule_count=0
for rule_file in "${HUB_RULES_DIR}"/*.yml; do
    [[ -f "${rule_file}" ]] || continue
    filename=$(basename "${rule_file}")

    # When CrowdSec is disabled, skip middlewares.yml and deploy
    # middlewares_nocrowdsec.yml in its place as hub_middlewares.yml
    if [ "${CROWDSEC_ENABLED}" = "false" ]; then
        if [ "${filename}" = "middlewares.yml" ]; then
            continue
        fi
        if [ "${filename}" = "middlewares_nocrowdsec.yml" ]; then
            cp "${rule_file}" "${RULES_DIR}/hub_middlewares.yml"
            printf "${GREEN}  Deployed: %s -> hub_middlewares.yml${NC}\n" "${filename}"
            rule_count=$((rule_count + 1))
            continue
        fi
    else
        # When CrowdSec is enabled, skip the no-CrowdSec variant entirely
        if [ "${filename}" = "middlewares_nocrowdsec.yml" ]; then
            continue
        fi
    fi

    target="hub_${filename}"
    cp "${rule_file}" "${RULES_DIR}/${target}"
    printf "${GREEN}  Deployed: %s -> %s${NC}\n" "${filename}" "${target}"
    rule_count=$((rule_count + 1))
done

printf "${GREEN}Deployed %d hub Traefik rule(s)${NC}\n" "${rule_count}"
