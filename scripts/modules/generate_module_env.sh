#!/usr/bin/env bash
# ==============================================================================
# GENERATE MODULE ENV - Merge base.env + module .env.example + overrides
# ==============================================================================
# Description: Creates the .env file for a module by merging layers
# Author: Matt Barham
# Created: 2026-02-12
# Modified: 2026-02-12
# Version: 1.1.0
# ==============================================================================
# Usage: generate_module_env.sh MODULE_NAME [--force]
# Merge order (later wins):
#   1. shared/env/base.env (instance-wide)
#   2. modules/{name}/.env.example (module defaults)
#   3. modules.yml env_overrides (site-specific)
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

SPOKE_DIR="${SPOKE_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
MODULES_DIR="${SPOKE_DIR}/modules"
MODULES_YML="${SPOKE_DIR}/modules.yml"
BASE_ENV="${SPOKE_DIR}/shared/env/base.env"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

MODULE="${1:-}"
FORCE="${2:-}"

if [[ -z "${MODULE}" ]]; then
    printf "${RED}ERROR: Module name required${NC}\n" >&2
    printf "${YELLOW}Usage: %s MODULE_NAME [--force]${NC}\n" "$0" >&2
    exit 1
fi

MODULE_DIR="${MODULES_DIR}/${MODULE}"
MODULE_ENV_EXAMPLE="${MODULE_DIR}/.env.example"
TARGET_ENV="${MODULE_DIR}/.env"
TODAY_DATE=$(date --iso=date)

# Validate inputs
if [[ ! -f "${BASE_ENV}" ]]; then
    printf "${RED}ERROR: Base env not found: %s${NC}\n" "${BASE_ENV}" >&2
    printf "${YELLOW}Copy base.env.example to shared/env/base.env${NC}\n" >&2
    exit 1
fi

if [[ ! -d "${MODULE_DIR}" ]]; then
    printf "${RED}ERROR: Module directory not found: %s${NC}\n" "${MODULE_DIR}" >&2
    exit 1
fi

# Check if regeneration needed
NEEDS_REGEN=false
if [[ ! -f "${TARGET_ENV}" ]]; then
    printf "${YELLOW}Target .env missing, generating...${NC}\n"
    NEEDS_REGEN=true
elif [[ "${FORCE}" == "--force" ]]; then
    printf "${YELLOW}Force regeneration requested...${NC}\n"
    NEEDS_REGEN=true
elif [[ "${BASE_ENV}" -nt "${TARGET_ENV}" ]]; then
    printf "${YELLOW}base.env newer than target, regenerating...${NC}\n"
    NEEDS_REGEN=true
elif [[ -f "${MODULE_ENV_EXAMPLE}" && "${MODULE_ENV_EXAMPLE}" -nt "${TARGET_ENV}" ]]; then
    printf "${YELLOW}Module .env.example newer than target, regenerating...${NC}\n"
    NEEDS_REGEN=true
elif [[ "${MODULES_YML}" -nt "${TARGET_ENV}" ]]; then
    printf "${YELLOW}modules.yml newer than target, regenerating...${NC}\n"
    NEEDS_REGEN=true
fi

if [[ "${NEEDS_REGEN}" != "true" ]]; then
    printf "${GREEN}Environment file up to date for %s${NC}\n" "${MODULE}"
    exit 0
fi

printf "${BLUE}Generating %s...${NC}\n" "${TARGET_ENV}"

# Build the merged .env
{
    printf "# Generated environment file for %s module\n" "${MODULE}"
    printf "# Generated: %s\n" "$(date -Iseconds)"
    printf "# DO NOT EDIT - Regenerated automatically\n"
    printf "\n"
    printf "BUILD_DATE=%s\n" "${TODAY_DATE}"
    printf "\n"

    # Layer 1: Base environment
    printf "# === BASE CONFIGURATION ===\n"
    cat "${BASE_ENV}"
    printf "\n"

    # Layer 2: Module .env.example (if exists)
    if [[ -f "${MODULE_ENV_EXAMPLE}" ]]; then
        printf "# === %s MODULE CONFIGURATION ===\n" "$(echo "${MODULE}" | tr '[:lower:]' '[:upper:]')"
        cat "${MODULE_ENV_EXAMPLE}"
        printf "\n"
    fi

    # Layer 3: modules.yml env_overrides
    if command -v yq &>/dev/null && [[ -f "${MODULES_YML}" ]]; then
        overrides=$(yq -r ".modules.${MODULE}.env_overrides // {} | to_entries | .[] | .key + \"=\" + (.value | tostring)" "${MODULES_YML}" 2>/dev/null || true)
        if [[ -n "${overrides}" ]]; then
            printf "# === SITE-SPECIFIC OVERRIDES (from modules.yml) ===\n"
            printf "%s\n" "${overrides}"
            printf "\n"
        fi
    fi
} > "${TARGET_ENV}"

printf "${GREEN}Environment file generated for %s${NC}\n" "${MODULE}"

# Warn if .env.example redefines critical hub variables
HUB_VARS="SPOKE_DIR SECRETS_DIR APPDATA_DIR DOMAIN"
if [[ -f "${MODULE_ENV_EXAMPLE}" ]]; then
    for hub_var in ${HUB_VARS}; do
        if grep -q "^${hub_var}=" "${MODULE_ENV_EXAMPLE}" 2>/dev/null; then
            # Check if modules.yml explicitly overrides this var
            has_override="false"
            if command -v yq &>/dev/null && [[ -f "${MODULES_YML}" ]]; then
                override_val=$(yq -r ".modules.${MODULE}.env_overrides.${hub_var} // empty" "${MODULES_YML}" 2>/dev/null || true)
                if [[ -n "${override_val}" ]]; then
                    has_override="true"
                fi
            fi
            if [[ "${has_override}" == "false" ]]; then
                example_val=$(grep "^${hub_var}=" "${MODULE_ENV_EXAMPLE}" | head -1 | cut -d= -f2-)
                base_val=$(grep "^${hub_var}=" "${BASE_ENV}" | head -1 | cut -d= -f2- || true)
                if [[ -n "${base_val}" && "${example_val}" != "${base_val}" ]]; then
                    printf "${YELLOW}  WARN: .env.example redefines hub variable %s=%s (base.env has %s)${NC}\n" "${hub_var}" "${example_val}" "${base_val}"
                    printf "${YELLOW}    Fix: Add env_overrides.%s in modules.yml, or remove from .env.example${NC}\n" "${hub_var}"
                fi
            fi
        fi
    done
fi

# Validate that compose file variables are satisfied
COMPOSE_FILE="${MODULE_DIR}/docker-compose.yml"
if [[ -f "${COMPOSE_FILE}" ]]; then
    printf "${BLUE}Validating environment variables...${NC}\n"

    REQUIRED_VARS=$(grep -v '^#' "${COMPOSE_FILE}" | grep -o '\${[^:}]*}' | sed 's/\${//g' | sed 's/}//g' | sort -u || true)
    MISSING_VARS=""

    for var in ${REQUIRED_VARS}; do
        if ! grep -q "^${var}=" "${TARGET_ENV}"; then
            MISSING_VARS="${MISSING_VARS} ${var}"
        fi
    done

    if [[ -n "${MISSING_VARS}" ]]; then
        printf "${YELLOW}WARNING: Variables referenced in compose but not in env:%s${NC}\n" "${MISSING_VARS}"
        printf "${YELLOW}These may be set by Docker Compose extensions or defaults${NC}\n"
    else
        printf "${GREEN}All compose variables satisfied${NC}\n"
    fi
fi
