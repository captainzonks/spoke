#!/usr/bin/env bash
# ==============================================================================
# SPOKE - MANAGE CROWDSEC SCENARIOS
# ==============================================================================
# Description: Manage CrowdSec scenarios, check alerts, and debug false positives
# Author: Matt Barham
# Created: 2025-08-06
# Modified: 2026-04-22
# Version: 2.0.1
# Host: Your Server
# ==============================================================================
# Type: Shell Script (Bash)
# Component: Spoke / maintenance (crowdsec admin)
# Security Level: MEDIUM - Mutates CrowdSec runtime (scenarios, decisions)
# ==============================================================================
# Dependencies:
#   - docker and docker-compose
#   - CrowdSec container running
#   - jq for JSON parsing
# ==============================================================================

set -euo pipefail

# Configuration
CROWDSEC_CONTAINER="crowdsec"

# Set SPOKE_DIR via environment or auto-detect from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOKE_DIR="${SPOKE_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

COMPOSE_DIR="${SPOKE_DIR}/hub"
CONFIG_DIR="${SPOKE_DIR}/appdata/crowdsec/config"
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_crowdsec_running() {
    if ! docker ps --filter "name=${CROWDSEC_CONTAINER}" --format "{{.Names}}" | grep -q "${CROWDSEC_CONTAINER}"; then
        log_error "CrowdSec container is not running"
        return 1
    fi
    return 0
}

exec_cscli() {
    docker exec "${CROWDSEC_CONTAINER}" cscli "$@"
}

show_alerts() {
    log_info "Recent CrowdSec alerts:"
    exec_cscli alerts list --limit 20 || {
        log_error "Failed to get alerts"
        return 1
    }
}

show_decisions() {
    log_info "Current CrowdSec decisions (bans):"
    exec_cscli decisions list || {
        log_error "Failed to get decisions"
        return 1
    }
}

show_scenarios() {
    log_info "Installed scenarios:"
    exec_cscli scenarios list || {
        log_error "Failed to get scenarios"
        return 1
    }
}

check_http_probing_alerts() {
    log_info "Checking for http-probing alerts in last 24h:"
    exec_cscli alerts list --scenario "crowdsecurity/http-probing" --since 24h || {
        log_warning "No http-probing alerts found or command failed"
        return 1
    }
}

remove_decisions_for_ip() {
    local ip="$1"
    log_info "Removing decisions for IP: ${ip}"
    exec_cscli decisions delete --ip "${ip}" || {
        log_error "Failed to remove decisions for IP: ${ip}"
        return 1
    }
    log_success "Removed decisions for IP: ${ip}"
}

add_to_simulation() {
    local scenario="$1"
    local simulation_file="${CONFIG_DIR}/simulation.yaml"

    log_info "Adding ${scenario} to simulation mode"

    # Backup current simulation file
    cp "${simulation_file}" "${simulation_file}.backup.$(date +%Y%m%d_%H%M%S)"

    # Add to simulation
    if grep -q "scenarios:" "${simulation_file}"; then
        # Scenarios section exists, add to it
        if ! grep -q "${scenario}" "${simulation_file}"; then
            sed -i "/scenarios:/a\\  - ${scenario}" "${simulation_file}"
            log_success "Added ${scenario} to simulation mode"
        else
            log_warning "${scenario} already in simulation mode"
        fi
    else
        # Create scenarios section
        cat >> "${simulation_file}" << EOF

scenarios:
  - ${scenario}
EOF
        log_success "Created scenarios section and added ${scenario} to simulation mode"
    fi

    log_info "Restarting CrowdSec to apply changes..."
    docker compose -f "${COMPOSE_DIR}/docker-compose.yml" restart crowdsec
}

show_whitelist_info() {
    log_info "Current whitelist configurations:"
    find "${CONFIG_DIR}/postoverflows/s01-whitelist/" -name "*.yaml" -type f | while read -r file; do
        echo "=== $(basename "$file") ==="
        head -20 "$file"
        echo
    done
}

check_my_ip_status() {
    log_info "Checking if your current IP has any decisions:"
    local my_ip
    my_ip=$(curl -s https://ipv4.icanhazip.com/)
    log_info "Your current IP: ${my_ip}"

    exec_cscli decisions list --ip "${my_ip}" || {
        log_info "No decisions found for your IP (this is good!)"
        return 0
    }
}

test_firefox_patterns() {
    log_info "Testing Firefox/Arkenfox browser patterns in CrowdSec logs:"

    # Look for Firefox user agents in recent alerts
    exec_cscli alerts list --limit 50 | grep -i firefox || {
        log_info "No Firefox-related alerts found in recent activity"
    }

    # Check for http-probing alerts specifically
    log_info "Checking for http-probing alerts with Firefox patterns:"
    exec_cscli alerts list --scenario "crowdsecurity/http-probing" --since 24h | head -10
}

debug_http_probing() {
    log_info "Debugging http-probing scenario triggers:"

    # Show recent http-probing alerts with details
    log_info "Recent http-probing alerts:"
    exec_cscli alerts list --scenario "crowdsecurity/http-probing" --limit 10 -o json | jq -r '.[] | "\(.source.ip) - \(.created_at) - \(.scenario)"' 2>/dev/null || {
        log_warning "jq not available, showing raw output"
        exec_cscli alerts list --scenario "crowdsecurity/http-probing" --limit 5
    }

    # Check if simulation mode is active
    log_info "Checking simulation status:"
    if grep -q "http-probing" "${CONFIG_DIR}/simulation.yaml" 2>/dev/null; then
        log_success "http-probing is in simulation mode (good!)"
    else
        log_warning "http-probing is NOT in simulation mode"
    fi
}

test_whitelist_coverage() {
    log_info "Testing whitelist coverage for common patterns:"

    # List all custom whitelists
    log_info "Current custom whitelists:"
    find "${CONFIG_DIR}/postoverflows/s01-whitelist/" -name "[0-9][0-9]-*.yaml" -type f | sort | while read -r file; do
        filename=$(basename "$file")
        description=$(grep "description:" "$file" | sed 's/description: *"*\(.*\)"*/\1/')
        echo "  ${filename}: ${description}"
    done

    echo
    log_info "Hub whitelists (symlinks):"
    find "${CONFIG_DIR}/postoverflows/s01-whitelist/" -name "*.yaml" -type l | sort | while read -r file; do
        filename=$(basename "$file")
        target=$(readlink "$file")
        echo "  ${filename} -> ${target}"
    done
}

show_help() {
    cat << EOF
CrowdSec Scenario Management Script

Usage: $0 [OPTION]

Options:
    alerts          Show recent alerts
    decisions       Show current decisions (bans)
    scenarios       Show installed scenarios
    http-probing    Check for http-probing alerts
    simulate <scenario>  Add scenario to simulation mode
    whitelist       Show current whitelist configurations
    unban <ip>      Remove decisions for specific IP
    my-ip           Check if your IP is banned
    firefox-test    Test Firefox/Arkenfox browsing patterns
    debug-probing   Debug http-probing scenario triggers
    whitelist-test  Test whitelist coverage and show all whitelists
    help            Show this help message

Examples:
    $0 alerts
    $0 simulate crowdsecurity/http-probing
    $0 unban 192.168.1.100
    $0 firefox-test
    $0 debug-probing

EOF
}

# Main logic
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # Check if CrowdSec is running
    if ! check_crowdsec_running; then
        exit 1
    fi

    case "$1" in
        "alerts")
            show_alerts
            ;;
        "decisions")
            show_decisions
            ;;
        "scenarios")
            show_scenarios
            ;;
        "http-probing")
            check_http_probing_alerts
            ;;
        "simulate")
            if [[ $# -lt 2 ]]; then
                log_error "Please specify a scenario to simulate"
                exit 1
            fi
            add_to_simulation "$2"
            ;;
        "whitelist")
            show_whitelist_info
            ;;
        "unban")
            if [[ $# -lt 2 ]]; then
                log_error "Please specify an IP address to unban"
                exit 1
            fi
            remove_decisions_for_ip "$2"
            ;;
        "my-ip")
            check_my_ip_status
            ;;
        "firefox-test")
            test_firefox_patterns
            ;;
        "debug-probing")
            debug_http_probing
            ;;
        "whitelist-test")
            test_whitelist_coverage
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
