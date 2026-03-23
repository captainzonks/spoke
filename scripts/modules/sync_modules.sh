#!/usr/bin/env bash
# ==============================================================================
# SYNC MODULES - Clone or pull module repositories
# ==============================================================================
# Description: Reads modules.yml and clones/pulls enabled module repos
# Author: Matt Barham
# Created: 2026-02-12
# Version: 1.0.0
# ==============================================================================
# Usage: sync_modules.sh [MODULE_NAME]
#   No args: sync all enabled modules
#   MODULE_NAME: sync only the specified module
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

SPOKE_DIR="${SPOKE_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
MODULES_DIR="${SPOKE_DIR}/modules"
MODULES_YML="${SPOKE_DIR}/modules.yml"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ ! -f "${MODULES_YML}" ]]; then
    printf "${RED}ERROR: modules.yml not found at %s${NC}\n" "${MODULES_YML}" >&2
    printf "${YELLOW}Copy modules.yml.example to modules.yml and configure it${NC}\n" >&2
    exit 1
fi

# Check for yq (YAML parser)
if ! command -v yq &>/dev/null; then
    printf "${RED}ERROR: yq is required but not installed${NC}\n" >&2
    printf "${YELLOW}Install: https://github.com/mikefarah/yq${NC}\n" >&2
    exit 1
fi

mkdir -p "${MODULES_DIR}"

sync_module() {
    local name="$1"
    local repo ref enabled

    enabled=$(yq -r ".modules.${name}.enabled // false" "${MODULES_YML}")
    if [[ "${enabled}" != "true" ]]; then
        printf "${YELLOW}Skipping %s (disabled)${NC}\n" "${name}"
        return 0
    fi

    repo=$(yq -r ".modules.${name}.repo" "${MODULES_YML}")
    ref=$(yq -r ".modules.${name}.ref // \"main\"" "${MODULES_YML}")

    if [[ -z "${repo}" || "${repo}" == "null" ]]; then
        printf "${RED}ERROR: No repo defined for module %s${NC}\n" "${name}" >&2
        return 1
    fi

    local module_dir="${MODULES_DIR}/${name}"

    if [[ -d "${module_dir}/.git" ]]; then
        printf "${BLUE}Pulling %s (%s)...${NC}\n" "${name}" "${ref}"
        git -C "${module_dir}" fetch origin
        git -C "${module_dir}" checkout "${ref}" 2>/dev/null || git -C "${module_dir}" checkout -b "${ref}" "origin/${ref}"
        git -C "${module_dir}" pull origin "${ref}"
    else
        printf "${BLUE}Cloning %s from %s (%s)...${NC}\n" "${name}" "${repo}" "${ref}"
        git clone --branch "${ref}" "${repo}" "${module_dir}"
    fi

    printf "${GREEN}Synced %s${NC}\n" "${name}"
}

TARGET_MODULE="${1:-}"

if [[ -n "${TARGET_MODULE}" ]]; then
    sync_module "${TARGET_MODULE}"
else
    # Get all module names from modules.yml
    modules=$(yq -r '.modules | keys | .[]' "${MODULES_YML}")
    for module in ${modules}; do
        sync_module "${module}" || true
    done
fi

printf "${GREEN}Module sync complete${NC}\n"
