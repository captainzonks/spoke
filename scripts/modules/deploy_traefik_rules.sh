#!/usr/bin/env bash
# ==============================================================================
# DEPLOY TRAEFIK RULES - Copy module Traefik rules to hub rules directory
# ==============================================================================
# Description: Copies a module's traefik/ directory contents to appdata/traefik/rules/
#              with a mod_ prefix to prevent naming collisions
# Author: Matt Barham
# Created: 2026-02-12
# Version: 1.2.0
# ==============================================================================
# Usage: deploy_traefik_rules.sh MODULE_NAME
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

SPOKE_DIR="${SPOKE_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
MODULES_DIR="${SPOKE_DIR}/modules"
RULES_DIR="${SPOKE_DIR}/appdata/traefik/rules"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

MODULE="${1:-}"
if [[ -z "${MODULE}" ]]; then
    printf "${RED}ERROR: Module name required${NC}\n" >&2
    printf "${YELLOW}Usage: %s MODULE_NAME${NC}\n" "$0" >&2
    exit 1
fi

MODULE_DIR="${MODULES_DIR}/${MODULE}"
MODULE_TRAEFIK_DIR="${MODULE_DIR}/traefik"

if [[ ! -d "${MODULE_TRAEFIK_DIR}" ]]; then
    printf "${YELLOW}No traefik/ directory in %s, skipping rule deployment${NC}\n" "${MODULE}"
    exit 0
fi

mkdir -p "${RULES_DIR}"

# Find all .yml files in the module's traefik directory
rule_count=0
while IFS= read -r -d '' rule_file; do
    filename=$(basename "${rule_file}")
    target="mod_${MODULE}_${filename}"

    cp "${rule_file}" "${RULES_DIR}/${target}"
    printf "${GREEN}  Deployed: %s -> %s${NC}\n" "${filename}" "${target}"
    rule_count=$((rule_count + 1))
done < <(find "${MODULE_TRAEFIK_DIR}" -name '*.yml' -print0)

if [[ ${rule_count} -eq 0 ]]; then
    printf "${YELLOW}No .yml rule files found in %s${NC}\n" "${MODULE_TRAEFIK_DIR}"
else
    printf "${GREEN}Deployed %d Traefik rule(s) for %s${NC}\n" "${rule_count}" "${MODULE}"
fi

# Cross-reference audit: check this module's @file refs against all definitions
printf "${BLUE}Auditing Traefik references for ${MODULE}...${NC}\n"

audit_tmp=$(mktemp -d)
trap 'rm -rf "${audit_tmp}"' EXIT

# Collect all middleware + service definitions from ALL deployed rule files
# Definitions sit at 4-space indent under 2-space "middlewares:" or "services:" keys
if [[ -d "${RULES_DIR}" ]]; then
    for rule_file in "${RULES_DIR}"/*.yml; do
        [[ -f "${rule_file}" ]] || continue
        awk '
            /^  (middlewares|services):/ { in_sect=1; next }
            /^  [a-zA-Z]/               { in_sect=0 }
            /^[a-zA-Z]/                 { in_sect=0 }
            in_sect && /^    [a-zA-Z][-a-zA-Z0-9_]*:/ {
                name = $1; sub(/:.*/, "", name); print name
            }
        ' "${rule_file}"
    done | sort -u > "${audit_tmp}/defined"
fi

# Collect @file references only from THIS module's deployed rule files
for rule_file in "${RULES_DIR}"/mod_"${MODULE}"_*.yml; do
    [[ -f "${rule_file}" ]] || continue
    grep -v '^[[:space:]]*#' "${rule_file}" \
        | grep -oE '[a-zA-Z][-a-zA-Z0-9_]*@file' \
        | sed 's/@file//' || true
done | sort -u > "${audit_tmp}/refs"

# Compare: warn about referenced but undefined names
undefined_count=0
while IFS= read -r ref; do
    [[ -z "${ref}" ]] && continue
    if ! grep -qx "${ref}" "${audit_tmp}/defined" 2>/dev/null; then
        printf "${YELLOW}  WARN: '%s@file' referenced but not defined in any rule file${NC}\n" "${ref}"
        undefined_count=$((undefined_count + 1))
    fi
done < "${audit_tmp}/refs"

if [[ ${undefined_count} -gt 0 ]]; then
    printf "${YELLOW}  %d unresolved reference(s) — deploy modules that define them${NC}\n" "${undefined_count}"
elif [[ -s "${audit_tmp}/refs" ]]; then
    printf "${GREEN}  All references resolved${NC}\n"
fi
