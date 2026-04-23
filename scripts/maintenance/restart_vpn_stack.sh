#!/usr/bin/env bash
# ==============================================================================
# SPOKE - VPN STACK RESTART
# ==============================================================================
# Description: Properly restart gluetun and dependent containers
# Author: Matt Barham (with Claude Code assistance)
# Created: 2025-12-04
# Modified: 2026-04-22
# Version: 2.0.1
# Host: Your Server
# ==============================================================================
# Type: Shell Script (Bash)
# Component: Spoke / maintenance (VPN stack)
# Purpose: Handle container dependencies correctly when restarting VPN stack
# Issue: qbittorrent and slskd use gluetun's network namespace - restart order matters
# ==============================================================================
# Usage:
#   ./restart_vpn_stack.sh          # Restart all VPN-related containers
#   ./restart_vpn_stack.sh gluetun  # Restart only gluetun (stops deps first)
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === Configuration ===
GLUETUN_CONTAINER="gluetun"
DEPENDENT_CONTAINERS=("qbittorrent" "slskd" "qsticky")
MAX_WAIT_ATTEMPTS=30
WAIT_INTERVAL=2

# === Functions ===
print_header() {
    printf "${BLUE}===================================================================${NC}\n"
    printf "${BLUE}%s${NC}\n" "$1"
    printf "${BLUE}===================================================================${NC}\n"
}

print_status() {
    printf "${GREEN}[OK]${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}[!]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[X]${NC} %s\n" "$1"
}

stop_dependent_containers() {
    print_header "Stopping Dependent Containers"

    for container in "${DEPENDENT_CONTAINERS[@]}"; do
        if docker ps --filter "name=^${container}$" --format "{{.Names}}" | grep -q "^${container}$"; then
            printf "  Stopping ${YELLOW}%s${NC}..." "$container"
            if docker stop "$container" >/dev/null 2>&1; then
                printf " ${GREEN}done${NC}\n"
            else
                printf " ${RED}failed${NC}\n"
            fi
        else
            printf "  ${YELLOW}%s${NC} not running, skipping\n" "$container"
        fi
    done
    printf "\n"
}

restart_gluetun() {
    print_header "Restarting Gluetun"

    printf "  Restarting ${YELLOW}%s${NC}..." "$GLUETUN_CONTAINER"
    if docker restart "$GLUETUN_CONTAINER" >/dev/null 2>&1; then
        printf " ${GREEN}done${NC}\n\n"
    else
        print_error "Failed to restart gluetun"
        exit 1
    fi
}

wait_for_gluetun_healthy() {
    print_header "Waiting for Gluetun to be Healthy"

    for i in $(seq 1 $MAX_WAIT_ATTEMPTS); do
        STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$GLUETUN_CONTAINER" 2>/dev/null || echo "starting")

        if [[ "$STATUS" == "healthy" ]]; then
            print_status "Gluetun is healthy (attempt $i/$MAX_WAIT_ATTEMPTS)"
            printf "\n"
            return 0
        fi

        printf "  Attempt %02d/%02d: ${YELLOW}%s${NC}\n" "$i" "$MAX_WAIT_ATTEMPTS" "$STATUS"
        sleep $WAIT_INTERVAL
    done

    print_warning "Gluetun did not become healthy within $((MAX_WAIT_ATTEMPTS * WAIT_INTERVAL)) seconds"
    print_warning "Continuing anyway - dependent containers may have issues"
    printf "\n"
    return 1
}

start_dependent_containers() {
    print_header "Starting Dependent Containers"

    for container in "${DEPENDENT_CONTAINERS[@]}"; do
        printf "  Starting ${YELLOW}%s${NC}..." "$container"
        if docker start "$container" >/dev/null 2>&1; then
            printf " ${GREEN}done${NC}\n"
        else
            printf " ${RED}failed${NC}\n"
        fi
        sleep 2  # Brief pause between starts
    done
    printf "\n"
}

show_final_status() {
    print_header "Final Status"

    printf "\n"
    docker ps --filter "name=gluetun\|qbittorrent\|qsticky\|slskd" \
        --format "table {{.Names}}\t{{.Status}}\t{{.State}}"
    printf "\n"
}

verify_vpn_connectivity() {
    print_header "Verifying VPN Connectivity"

    # Check if qbittorrent is running first
    if ! docker ps --filter "name=^qbittorrent$" --format "{{.Names}}" | grep -q "^qbittorrent$"; then
        print_warning "qbittorrent not running, skipping VPN connectivity test"
        printf "\n"
        return
    fi

    printf "  Checking external IP via qbittorrent..."
    EXTERNAL_IP=$(docker exec qbittorrent curl -s --max-time 10 https://api.ipify.org 2>/dev/null || echo "FAILED")

    if [[ "$EXTERNAL_IP" == "FAILED" ]]; then
        print_error "Failed to get external IP"
    elif [[ "$EXTERNAL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_status "External IP: $EXTERNAL_IP"
    else
        print_warning "Unexpected response: $EXTERNAL_IP"
    fi
    printf "\n"
}

# === Main ===
main() {
    print_header "VPN Stack Restart"
    printf "\n"

    # Check if gluetun exists
    if ! docker ps -a --filter "name=^${GLUETUN_CONTAINER}$" --format "{{.Names}}" | grep -q "^${GLUETUN_CONTAINER}$"; then
        print_error "Gluetun container not found"
        exit 1
    fi

    # Stop dependent containers
    stop_dependent_containers

    # Restart gluetun
    restart_gluetun

    # Wait for gluetun to be healthy
    wait_for_gluetun_healthy

    # Start dependent containers
    start_dependent_containers

    # Show final status
    show_final_status

    # Verify VPN connectivity
    verify_vpn_connectivity

    print_header "VPN Stack Restart Complete"
}

# Run main function
main "$@"
