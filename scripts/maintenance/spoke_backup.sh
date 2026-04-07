#!/usr/bin/env bash
# ==============================================================================
# SPOKE CONFIG BACKUP
# ==============================================================================
# Description: Backup critical Spoke configuration to a local restic repository
# Author: Matt Barham
# Created: 2026-04-06
# Version: 1.0.0
# ==============================================================================
# Usage: ./spoke_backup.sh [--dry-run] [--verify]
#
# Backs up:
#   Core (always):
#     - secrets/              Docker secrets
#     - shared/env/           Environment files (base.env, hub.env)
#     - modules.yml           Module registry and site-specific config
#     - modules/*/docker-compose.override.yml  Site-specific compose overrides
#   Hub extras (from hub/backup.conf):
#     - appdata/traefik/rules/     Dynamic routing rules
#     - appdata/crowdsec/config/   CrowdSec custom config
#     - etc.
#   Per-module extras (from modules/{name}/backup.conf):
#     - appdata/{service}/config/  Service-specific config files
#     - etc.
#
# Each backup.conf is a simple text file:
#   - One path per line (relative to SPOKE_DIR or absolute)
#   - Lines starting with # are comments
#   - Blank lines are ignored
#
# Prerequisites:
#   - restic installed: sudo pacman -S restic
#   - Restic password file: secrets/restic/restic_password (create before first run)
#   - Backup destination: /mnt/backup/spoke-config (or set BACKUP_DEST env var)
#
# First run: initializes the restic repository automatically
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOKE_DIR="${SPOKE_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

BASE_ENV_FILE="${SPOKE_DIR}/shared/env/base.env"
HUB_ENV_FILE="${SPOKE_DIR}/shared/env/hub.env"

# Load environment so SECRETS_DIR, APPDATA_DIR etc. are available
for env_file in "${BASE_ENV_FILE}" "${HUB_ENV_FILE}"; do
    if [[ -f "${env_file}" ]]; then
        # shellcheck disable=SC1090
        source "${env_file}"
    else
        printf "ERROR: Environment file not found: %s\n" "${env_file}" >&2
        exit 1
    fi
done

# Backup destination (override with BACKUP_DEST env var)
BACKUP_DEST="${BACKUP_DEST:-/mnt/backup/spoke-config}"
RESTIC_PASSWORD_FILE="${SECRETS_DIR}/restic/restic_password"

# Retention policy (override with env vars)
RETAIN_DAILY="${RETAIN_DAILY:-7}"
RETAIN_WEEKLY="${RETAIN_WEEKLY:-4}"
RETAIN_MONTHLY="${RETAIN_MONTHLY:-3}"

# Flags
DRY_RUN=false
VERIFY=false

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

for arg in "$@"; do
    case "${arg}" in
        --dry-run)  DRY_RUN=true ;;
        --verify)   VERIFY=true ;;
        --help|-h)
            sed -n '/^# Usage/,/^# ====/p' "${BASH_SOURCE[0]}" | head -n -1 | sed 's/^# \?//'
            exit 0
            ;;
        *)
            printf "ERROR: Unknown argument: %s\n" "${arg}" >&2
            exit 1
            ;;
    esac
done

# ==============================================================================
# VALIDATION
# ==============================================================================

if ! command -v restic &>/dev/null; then
    printf "ERROR: restic not found. Install with: sudo pacman -S restic\n" >&2
    exit 1
fi

if [[ ! -f "${RESTIC_PASSWORD_FILE}" ]]; then
    printf "ERROR: Restic password file not found: %s\n" "${RESTIC_PASSWORD_FILE}" >&2
    printf "       Create it with: openssl rand -base64 32 > %s\n" "${RESTIC_PASSWORD_FILE}" >&2
    printf "       Then set permissions: chmod 640 %s\n" "${RESTIC_PASSWORD_FILE}" >&2
    exit 1
fi

if [[ ! -d "${BACKUP_DEST}" ]]; then
    printf "ERROR: Backup destination not found: %s\n" "${BACKUP_DEST}" >&2
    printf "       Create it or check that /mnt/backup is mounted\n" >&2
    exit 1
fi

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf "[%s] WARN: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# Resolve a path entry from a backup.conf file.
# Relative paths are resolved against SPOKE_DIR.
# Returns empty string if path does not exist.
resolve_path() {
    local entry="${1}"
    local resolved

    if [[ "${entry}" = /* ]]; then
        resolved="${entry}"
    else
        resolved="${SPOKE_DIR}/${entry}"
    fi

    if [[ -e "${resolved}" ]]; then
        printf "%s" "${resolved}"
    else
        warn "Backup path not found (skipping): ${resolved}"
    fi
}

# Read a backup.conf file and append valid paths to BACKUP_PATHS array.
load_conf() {
    local conf_file="${1}"
    local path resolved

    while IFS= read -r path || [[ -n "${path}" ]]; do
        # Skip blank lines and comments
        [[ -z "${path}" || "${path}" =~ ^[[:space:]]*# ]] && continue
        # Strip trailing whitespace
        path="${path%"${path##*[![:space:]]}"}"
        resolved="$(resolve_path "${path}")"
        if [[ -n "${resolved}" ]]; then
            BACKUP_PATHS+=("${resolved}")
        fi
    done < "${conf_file}"
}

# ==============================================================================
# COLLECT BACKUP PATHS
# ==============================================================================

declare -a BACKUP_PATHS=()

# --- Core paths (always included) ---

log "Collecting core backup paths..."

for core_path in \
    "${SPOKE_DIR}/secrets" \
    "${SPOKE_DIR}/shared/env" \
    "${SPOKE_DIR}/modules.yml"; do
    if [[ -e "${core_path}" ]]; then
        BACKUP_PATHS+=("${core_path}")
    else
        warn "Core path not found (skipping): ${core_path}"
    fi
done

# --- Auto-discover docker-compose.override.yml files ---

while IFS= read -r -d '' override_file; do
    BACKUP_PATHS+=("${override_file}")
done < <(find "${SPOKE_DIR}/modules" -maxdepth 2 -name "docker-compose.override.yml" -print0 2>/dev/null)

# --- Hub backup.conf ---

HUB_CONF="${SPOKE_DIR}/hub/backup.conf"
if [[ -f "${HUB_CONF}" ]]; then
    log "Loading hub backup config: ${HUB_CONF}"
    load_conf "${HUB_CONF}"
fi

# --- Per-module backup.conf files ---

while IFS= read -r -d '' module_conf; do
    module_name="$(basename "$(dirname "${module_conf}")")"
    log "Loading module backup config: ${module_name}"
    load_conf "${module_conf}"
done < <(find "${SPOKE_DIR}/modules" -maxdepth 2 -name "backup.conf" -print0 2>/dev/null | sort -z)

# ==============================================================================
# DRY RUN: REPORT ONLY
# ==============================================================================

if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY RUN — paths that would be backed up (${#BACKUP_PATHS[@]} total):"
    for path in "${BACKUP_PATHS[@]}"; do
        printf "  %s\n" "${path}"
    done
    exit 0
fi

# ==============================================================================
# RESTIC BACKUP
# ==============================================================================

export RESTIC_REPOSITORY="${BACKUP_DEST}"
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE}"

# Initialize repo if needed
if ! restic snapshots &>/dev/null 2>&1; then
    log "Initializing restic repository at ${BACKUP_DEST}"
    restic init
fi

log "Starting backup (${#BACKUP_PATHS[@]} paths)..."

restic backup \
    --tag spoke-config \
    --tag "$(hostname)" \
    "${BACKUP_PATHS[@]}"

# ==============================================================================
# RETENTION POLICY
# ==============================================================================

log "Applying retention policy (daily=${RETAIN_DAILY}, weekly=${RETAIN_WEEKLY}, monthly=${RETAIN_MONTHLY})..."

restic forget \
    --tag spoke-config \
    --keep-daily  "${RETAIN_DAILY}" \
    --keep-weekly "${RETAIN_WEEKLY}" \
    --keep-monthly "${RETAIN_MONTHLY}" \
    --prune

# ==============================================================================
# OPTIONAL VERIFY
# ==============================================================================

if [[ "${VERIFY}" == "true" ]]; then
    log "Verifying repository integrity..."
    restic check
fi

log "Backup complete."
