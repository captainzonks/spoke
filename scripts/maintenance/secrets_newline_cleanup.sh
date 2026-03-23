#!/usr/bin/env bash
# ==============================================================================
# SECRETS_NEWLINE_CLEANUP.SH
# ==============================================================================
# Description: Systematically remove trailing newlines from Docker secrets files
# Author: Matt Barham
# Created: 2025-09-07
# Modified: 2026-02-19
# Version: 2.0.0
# ==============================================================================
# Requirements:
#   - Bash 4.0+
#   - find, tr, printf commands
#   - Access to SPOKE_DIR/secrets directory
# Security Notes:
#   - Creates backups before modification
#   - Preserves file permissions and ownership
#   - Validates file integrity after changes
#   - Logs all modifications for audit trail
# Documentation:
#   - Fixes trailing newline issues with Docker secrets
#   - Compatible with all secret file formats (no size limits)
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Secure Internal Field Separator

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Script configuration
readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DATE="$(date '+%Y-%m-%d_%H-%M-%S')"

# Default paths (override with environment variables)
readonly SPOKE_DIR="${SPOKE_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
readonly SECRETS_DIR="${SPOKE_DIR}/secrets"
readonly BACKUP_DIR="${SPOKE_DIR}/backups/secrets_cleanup_${LOG_DATE}"
readonly LOG_FILE="${BACKUP_DIR}/cleanup_log.txt"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

log() {
    local message="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_line="${timestamp} [INFO] ${message}"

    # Output to stderr always
    printf "%s\n" "${log_line}" >&2

    # Also log to file if backup directory exists
    if [[ -d "${BACKUP_DIR}" ]]; then
        printf "%s\n" "${log_line}" >> "${LOG_FILE}"
    fi
}

error() {
    local message="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_line="${timestamp} [ERROR] ${message}"

    # Output to stderr with color
    printf "${RED}%s${NC}\n" "${log_line}" >&2

    # Also log to file if backup directory exists (without color codes)
    if [[ -d "${BACKUP_DIR}" ]]; then
        printf "%s\n" "${log_line}" >> "${LOG_FILE}"
    fi
}

warning() {
    local message="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_line="${timestamp} [WARNING] ${message}"

    # Output to stderr with color
    printf "${YELLOW}%s${NC}\n" "${log_line}" >&2

    # Also log to file if backup directory exists (without color codes)
    if [[ -d "${BACKUP_DIR}" ]]; then
        printf "%s\n" "${log_line}" >> "${LOG_FILE}"
    fi
}

success() {
    local message="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_line="${timestamp} [SUCCESS] ${message}"

    # Output to stderr with color
    printf "${GREEN}%s${NC}\n" "${log_line}" >&2

    # Also log to file if backup directory exists (without color codes)
    if [[ -d "${BACKUP_DIR}" ]]; then
        printf "%s\n" "${log_line}" >> "${LOG_FILE}"
    fi
}

info() {
    local message="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_line="${timestamp} [INFO] ${message}"

    # Output to stderr with color
    printf "${BLUE}%s${NC}\n" "${log_line}" >&2

    # Also log to file if backup directory exists (without color codes)
    if [[ -d "${BACKUP_DIR}" ]]; then
        printf "%s\n" "${log_line}" >> "${LOG_FILE}"
    fi
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

cleanup_on_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        error "Script failed with exit code ${exit_code}"
        if [[ -f "${LOG_FILE}" ]]; then
            error "Check log file: ${LOG_FILE}"
        fi
        if [[ -d "${BACKUP_DIR}" ]]; then
            warning "Backup available at: ${BACKUP_DIR}"
        fi
    fi
    exit ${exit_code}
}

validate_environment() {
    log "Validating environment and dependencies..."

    # Check if running as correct user
    if [[ "${EUID}" -eq 0 ]]; then
        error "Do not run this script as root"
        error "Run as user with access to Docker secrets directory"
        exit 1
    fi

    # Check if secrets directory exists
    if [[ ! -d "${SECRETS_DIR}" ]]; then
        error "Secrets directory not found: ${SECRETS_DIR}"
        error "Set SPOKE_DIR environment variable if needed"
        exit 1
    fi

    # Check if we can read secrets directory
    if [[ ! -r "${SECRETS_DIR}" ]]; then
        error "Cannot read secrets directory: ${SECRETS_DIR}"
        error "Check permissions or group membership"
        exit 1
    fi

    # Check required commands
    local required_commands=("find" "tr" "printf" "stat" "cp")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            error "Required command not found: ${cmd}"
            exit 1
        fi
    done

    success "Environment validation completed"
}

create_backup_directory() {
    log "Creating backup directory..."

    if ! mkdir -p "${BACKUP_DIR}"; then
        error "Failed to create backup directory: ${BACKUP_DIR}"
        exit 1
    fi

    # Create log file
    touch "${LOG_FILE}"

    success "Backup directory created: ${BACKUP_DIR}"
}

# ==============================================================================
# BACKUP FUNCTIONS
# ==============================================================================

backup_secrets_structure() {
    log "Creating complete backup of secrets structure..."

    # Create directory structure
    if ! cp -r "${SECRETS_DIR}" "${BACKUP_DIR}/original_secrets"; then
        error "Failed to backup secrets directory"
        exit 1
    fi

    # Create manifest of original files
    local manifest_file="${BACKUP_DIR}/original_manifest.txt"
    {
        printf "# Secrets backup manifest - %s\n" "$(date)"
        printf "# Original secrets directory: %s\n" "${SECRETS_DIR}"
        printf "# Backup location: %s\n\n" "${BACKUP_DIR}/original_secrets"

        find "${SECRETS_DIR}" -type f -exec stat --format="%n|%s|%Y|%a|%U:%G" {} \;
    } > "${manifest_file}"

    success "Secrets structure backed up successfully"
}

# ==============================================================================
# ANALYSIS FUNCTIONS
# ==============================================================================

analyze_secrets_files() {
    log "Analyzing secrets files for trailing newlines..."

    local analysis_file="${BACKUP_DIR}/analysis_report.txt"
    local files_with_newlines=0
    local total_files=0

    {
        printf "# Secrets Analysis Report - %s\n" "$(date)"
        printf "# Secrets directory: %s\n\n" "${SECRETS_DIR}"
        printf "%-60s | %-8s | %-12s | %-10s\n" "File Path" "Size" "Has Newline" "Type"
        printf "%s\n" "$(printf '=%.0s' {1..100})"
    } > "${analysis_file}"

    while IFS= read -r -d '' file; do
        total_files=$((total_files + 1))

        local relative_path="${file#${SECRETS_DIR}/}"
        local file_size
        file_size="$(stat --format='%s' "${file}")"

        # Check if file ends with newline
        local has_newline="No"
        if [[ -s "${file}" ]] && [[ "$(tail -c1 "${file}" | wc -l)" -gt 0 ]]; then
            has_newline="Yes"
            files_with_newlines=$((files_with_newlines + 1))
        fi

        # Determine file type based on content or extension
        local file_type="Secret"
        if [[ "${file}" == *.pem ]] || [[ "${file}" == *.crt ]]; then
            file_type="Cert"
        elif [[ "${file}" == *.key ]]; then
            file_type="Key"
        elif [[ "${file}" == *token* ]] || [[ "${file}" == *api* ]]; then
            file_type="Token"
        fi

        printf "%-60s | %-8s | %-12s | %-10s\n" \
            "${relative_path}" "${file_size}" "${has_newline}" "${file_type}" >> "${analysis_file}"

    done < <(find "${SECRETS_DIR}" -type f -print0)

    {
        printf "\n%s\n" "$(printf '=%.0s' {1..100})"
        printf "Summary:\n"
        printf "  Total files analyzed: %d\n" "${total_files}"
        printf "  Files with trailing newlines: %d\n" "${files_with_newlines}"
        printf "  Files that need cleanup: %d\n" "${files_with_newlines}"
    } >> "${analysis_file}"

    info "Analysis complete. Files needing cleanup: ${files_with_newlines}/${total_files}"
    info "Detailed analysis saved to: ${analysis_file}"

    # Display summary to user
    if [[ ${files_with_newlines} -eq 0 ]]; then
        success "No files have trailing newlines - no cleanup needed!"
        return 1
    fi

    return 0
}

# ==============================================================================
# CLEANUP FUNCTIONS
# ==============================================================================

remove_trailing_newlines() {
    log "Starting trailing newline removal process..."

    local cleanup_log="${BACKUP_DIR}/cleanup_details.txt"
    local files_modified=0
    local files_skipped=0

    {
        printf "# Cleanup Details Report - %s\n" "$(date)"
        printf "# Action: Remove trailing newlines from Docker secrets\n\n"
    } > "${cleanup_log}"

    while IFS= read -r -d '' file; do
        local relative_path="${file#${SECRETS_DIR}/}"

        # Skip if file is empty
        if [[ ! -s "${file}" ]]; then
            files_skipped=$((files_skipped + 1))
            printf "SKIPPED (empty): %s\n" "${relative_path}" >> "${cleanup_log}"
            continue
        fi

        # Check if file ends with newline
        if [[ "$(tail -c1 "${file}" | wc -l)" -eq 0 ]]; then
            files_skipped=$((files_skipped + 1))
            printf "SKIPPED (no newline): %s\n" "${relative_path}" >> "${cleanup_log}"
            continue
        fi

        # Store original file info
        local original_size
        original_size="$(stat --format='%s' "${file}")"
        local original_checksum
        original_checksum="$(sha256sum "${file}" | cut -d' ' -f1)"

        info "Processing: ${relative_path}"

        # Create individual file backup
        local file_backup="${BACKUP_DIR}/individual_backups/$(dirname "${relative_path}")"
        mkdir -p "${file_backup}"
        cp "${file}" "${file_backup}/$(basename "${file}").backup"

        # Remove trailing newline using a safer method
        local temp_file
        temp_file="$(mktemp)"

        # Use head to read all but the last character if file ends with newline
        if [[ "$(tail -c1 "${file}" | wc -l)" -gt 0 ]]; then
            # File ends with newline, remove it
            local file_size_minus_one=$((original_size - 1))
            if head -c "${file_size_minus_one}" "${file}" > "${temp_file}"; then
                # Verify the content is correct (not empty, reasonable size)
                local new_size
                new_size="$(stat --format='%s' "${temp_file}")"

                if [[ ${new_size} -eq ${file_size_minus_one} ]] && [[ ${new_size} -gt 0 ]]; then
                    # Move cleaned file to original location
                    if mv "${temp_file}" "${file}"; then
                        # Preserve original permissions and ownership
                        local original_perms
                        original_perms="$(stat --format='%a' "${file_backup}/$(basename "${file}").backup")"
                        chmod "${original_perms}" "${file}"

                        local original_owner
                        original_owner="$(stat --format='%U:%G' "${file_backup}/$(basename "${file}").backup")"
                        chown "${original_owner}" "${file}" 2>/dev/null || true

                        files_modified=$((files_modified + 1))

                        local new_checksum
                        new_checksum="$(sha256sum "${file}" | cut -d' ' -f1)"

                        printf "MODIFIED: %s | Size: %d->%d | Original: %s | New: %s\n" \
                            "${relative_path}" "${original_size}" "${new_size}" \
                            "${original_checksum:0:16}" "${new_checksum:0:16}" >> "${cleanup_log}"

                        success "Cleaned: ${relative_path}"
                    else
                        error "Failed to move cleaned file: ${relative_path}"
                        rm -f "${temp_file}"
                    fi
                else
                    error "Size validation failed for: ${relative_path}"
                    error "Expected: ${file_size_minus_one}, Got: ${new_size}"
                    rm -f "${temp_file}"
                fi
            else
                error "Failed to create cleaned version of: ${relative_path}"
                rm -f "${temp_file}"
            fi
        else
            # File doesn't end with newline (shouldn't happen due to our filtering)
            warning "File doesn't end with newline but was marked for cleanup: ${relative_path}"
            rm -f "${temp_file}"
        fi

    done < <(find "${SECRETS_DIR}" -type f -print0)

    {
        printf "\nCleanup Summary:\n"
        printf "  Files modified: %d\n" "${files_modified}"
        printf "  Files skipped: %d\n" "${files_skipped}"
        printf "  Total processed: %d\n" "$((files_modified + files_skipped))"
    } >> "${cleanup_log}"

    success "Cleanup process completed"
    success "Files modified: ${files_modified}"
    success "Detailed log: ${cleanup_log}"
}

# ==============================================================================
# VERIFICATION FUNCTIONS
# ==============================================================================

verify_cleanup() {
    log "Verifying cleanup results..."

    local verification_log="${BACKUP_DIR}/verification_report.txt"
    local files_with_newlines=0
    local total_files=0

    {
        printf "# Verification Report - %s\n" "$(date)"
        printf "# Post-cleanup analysis of secrets files\n\n"
    } > "${verification_log}"

    while IFS= read -r -d '' file; do
        total_files=$((total_files + 1))

        local relative_path="${file#${SECRETS_DIR}/}"

        # Check if file still ends with newline
        if [[ -s "${file}" ]] && [[ "$(tail -c1 "${file}" | wc -l)" -gt 0 ]]; then
            files_with_newlines=$((files_with_newlines + 1))
            printf "STILL HAS NEWLINE: %s\n" "${relative_path}" >> "${verification_log}"
            warning "File still has trailing newline: ${relative_path}"
        fi

    done < <(find "${SECRETS_DIR}" -type f -print0)

    {
        printf "\nVerification Summary:\n"
        printf "  Total files checked: %d\n" "${total_files}"
        printf "  Files still with newlines: %d\n" "${files_with_newlines}"
    } >> "${verification_log}"

    if [[ ${files_with_newlines} -eq 0 ]]; then
        success "Verification passed - no trailing newlines found!"
    else
        warning "Verification found ${files_with_newlines} files still with newlines"
        warning "Check verification report: ${verification_log}"
    fi

    info "Verification complete. Report saved to: ${verification_log}"
}

# ==============================================================================
# REPORTING FUNCTIONS
# ==============================================================================

generate_final_report() {
    log "Generating final report..."

    local final_report="${BACKUP_DIR}/final_report.txt"

    {
        printf "# Docker Secrets Trailing Newline Cleanup - Final Report\n"
        printf "# Generated: %s\n" "$(date)"
        printf "# Script: %s v2.0.0\n\n" "${SCRIPT_NAME}"

        printf "## Execution Summary\n"
        printf -- "- Secrets directory: %s\n" "${SECRETS_DIR}"
        printf -- "- Backup location: %s\n" "${BACKUP_DIR}"
        printf -- "- Log file: %s\n" "${LOG_FILE}"
        printf -- "- Started: %s\n" "${LOG_DATE}"
        printf -- "- Completed: %s\n\n" "$(date '+%Y-%m-%d_%H-%M-%S')"

        printf "## Reports Generated\n"
        printf -- "- Analysis report: analysis_report.txt\n"
        printf -- "- Cleanup details: cleanup_details.txt\n"
        printf -- "- Verification report: verification_report.txt\n"
        printf -- "- Original manifest: original_manifest.txt\n\n"

        printf "## Backup Structure\n"
        printf -- "- Full backup: original_secrets/\n"
        printf -- "- Individual backups: individual_backups/\n"
        printf -- "- Checksums preserved in cleanup details\n\n"

        printf "## Recovery Instructions\n"
        printf "To restore from backup if needed:\n"
        printf "  cp -r %s/original_secrets/* %s/\n\n" "${BACKUP_DIR}" "${SECRETS_DIR}"

        printf "## Validation\n"
        printf -- "- All modifications logged with checksums\n"
        printf -- "- File permissions and ownership preserved\n"
        printf -- "- Original files backed up individually\n"
        printf -- "- Post-cleanup verification performed\n\n"

        printf "## Next Steps\n"
        printf "1. Test Docker services to ensure secrets work correctly\n"
        printf "2. Monitor logs for any authentication issues\n"
        printf "3. Clean up backup directory after validation (optional)\n"
        printf "4. Update secret creation process to prevent future newlines\n\n"

        printf "## Prevention\n"
        printf "To prevent trailing newlines in future:\n"
        printf -- "- Use: printf '%%s' 'secret_value' > secret_file\n"
        printf -- "- Use: echo -n 'secret_value' > secret_file\n"
        printf -- "- Avoid: echo 'secret_value' > secret_file\n\n"

    } > "${final_report}"

    success "Final report generated: ${final_report}"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Systematically remove trailing newlines from Docker secrets files.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Analyze only, don't modify files
    -v, --verbose       Enable verbose output
    --backup-only       Create backup without cleanup
    --verify-only       Verify previous cleanup results

ENVIRONMENT VARIABLES:
    SPOKE_DIR           Spoke directory path (default: auto-detected from script location)

EXAMPLES:
    ${SCRIPT_NAME}                    # Full cleanup with backup
    ${SCRIPT_NAME} --dry-run          # Analysis only
    ${SCRIPT_NAME} --backup-only      # Backup without changes

EOF
}

main() {
    local dry_run=false
    local backup_only=false
    local verify_only=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            --backup-only)
                backup_only=true
                shift
                ;;
            --verify-only)
                verify_only=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Set up exit trap
    trap cleanup_on_exit EXIT

    # Main execution flow
    log "Starting Docker secrets trailing newline cleanup"
    log "Script: ${SCRIPT_NAME} v2.0.0"
    log "Spoke directory: ${SPOKE_DIR}"

    validate_environment
    create_backup_directory
    backup_secrets_structure

    if [[ "${verify_only}" == true ]]; then
        verify_cleanup
        generate_final_report
        return 0
    fi

    if ! analyze_secrets_files; then
        log "No cleanup needed - exiting"
        generate_final_report
        return 0
    fi

    if [[ "${backup_only}" == true ]]; then
        success "Backup completed - no cleanup performed"
        generate_final_report
        return 0
    fi

    if [[ "${dry_run}" == true ]]; then
        success "Dry run completed - no files modified"
        generate_final_report
        return 0
    fi

    # Confirm before cleanup
    printf "\n${YELLOW}WARNING: About to modify Docker secrets files${NC}\n"
    printf "Backup location: %s\n" "${BACKUP_DIR}"
    printf "Continue with cleanup? [y/N]: "
    read -r response

    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
        warning "Cleanup cancelled by user"
        generate_final_report
        exit 0
    fi

    remove_trailing_newlines
    verify_cleanup
    generate_final_report

    success "Docker secrets cleanup completed successfully!"
    success "Backup available at: ${BACKUP_DIR}"

    printf "\n${GREEN}Next steps:${NC}\n"
    printf "1. Test Docker services to ensure secrets work correctly\n"
    printf "2. Monitor logs for any authentication issues\n"
    printf "3. Review final report: %s/final_report.txt\n" "${BACKUP_DIR}"
}

# Execute main function with all arguments
main "$@"
