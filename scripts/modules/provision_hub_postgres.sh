#!/usr/bin/env bash
# ==============================================================================
# PROVISION HUB POSTGRES - Create databases and users for modules
# ==============================================================================
# Description: Reads hub_postgres section from a module's stack.yml and
#              provisions databases and users in the hub postgres-hub container
# Author: Matt Barham
# Created: 2026-02-13
# Modified: 2026-02-13
# Version: 1.0.0
# ==============================================================================
# Usage: provision_hub_postgres.sh MODULE_NAME
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

MODULE="${1:-}"
if [[ -z "${MODULE}" ]]; then
    printf "${RED}ERROR: Module name required${NC}\n" >&2
    printf "${YELLOW}Usage: %s MODULE_NAME${NC}\n" "$0" >&2
    exit 1
fi

MODULE_DIR="${MODULES_DIR}/${MODULE}"
STACK_YML="${MODULE_DIR}/stack.yml"

if [[ ! -f "${STACK_YML}" ]]; then
    printf "${YELLOW}No stack.yml found for %s, skipping postgres provisioning${NC}\n" "${MODULE}"
    exit 0
fi

if ! command -v yq &>/dev/null; then
    printf "${RED}ERROR: yq is required for hub_postgres provisioning${NC}\n" >&2
    exit 1
fi

# Check if module declares hub_postgres
has_hub_postgres=$(yq -r '.hub_postgres // empty' "${STACK_YML}" 2>/dev/null)
if [[ -z "${has_hub_postgres}" ]]; then
    printf "${BLUE}Module %s does not use hub postgres, skipping${NC}\n" "${MODULE}"
    exit 0
fi

# Verify postgres-hub container is running
if ! docker ps --format '{{.Names}}' | grep -q '^postgres-hub$'; then
    printf "${RED}ERROR: postgres-hub container is not running${NC}\n" >&2
    printf "${YELLOW}  Deploy the hub first: make hub-deploy${NC}\n" >&2
    exit 1
fi

printf "${BLUE}Provisioning hub postgres for module: %s${NC}\n" "${MODULE}"

# Read hub postgres admin credentials
PGUSER=$(yq -r '.hub_postgres.admin_user // "postgres"' "${STACK_YML}" 2>/dev/null)

# Process each database declared in hub_postgres.databases
db_count=$(yq -r '.hub_postgres.databases | length' "${STACK_YML}" 2>/dev/null)
if [[ "${db_count}" == "0" ]] || [[ "${db_count}" == "null" ]]; then
    printf "${YELLOW}  No databases declared in hub_postgres${NC}\n"
    exit 0
fi

for i in $(seq 0 $((db_count - 1))); do
    db_name=$(yq -r ".hub_postgres.databases[${i}].name" "${STACK_YML}" 2>/dev/null)
    db_owner=$(yq -r ".hub_postgres.databases[${i}].owner" "${STACK_YML}" 2>/dev/null)

    if [[ -z "${db_name}" ]] || [[ "${db_name}" == "null" ]]; then
        continue
    fi

    printf "${BLUE}  Database: %s${NC}\n" "${db_name}"

    # Create database if it doesn't exist
    exists=$(docker exec postgres-hub psql -U "${PGUSER}" -tAc \
        "SELECT 1 FROM pg_database WHERE datname = '${db_name}';" 2>/dev/null || true)

    if [[ "${exists}" == "1" ]]; then
        printf "${GREEN}    Database %s already exists${NC}\n" "${db_name}"
    else
        docker exec postgres-hub psql -U "${PGUSER}" -c \
            "CREATE DATABASE ${db_name};" 2>/dev/null
        printf "${GREEN}    Created database: %s${NC}\n" "${db_name}"
    fi

    # Set owner if specified
    if [[ -n "${db_owner}" ]] && [[ "${db_owner}" != "null" ]]; then
        docker exec postgres-hub psql -U "${PGUSER}" -c \
            "ALTER DATABASE ${db_name} OWNER TO ${db_owner};" 2>/dev/null || true
    fi
done

# Process each user declared in hub_postgres.users
user_count=$(yq -r '.hub_postgres.users | length' "${STACK_YML}" 2>/dev/null)
if [[ "${user_count}" == "0" ]] || [[ "${user_count}" == "null" ]]; then
    printf "${YELLOW}  No users declared in hub_postgres${NC}\n"
    exit 0
fi

for i in $(seq 0 $((user_count - 1))); do
    username=$(yq -r ".hub_postgres.users[${i}].name" "${STACK_YML}" 2>/dev/null)
    secret_name=$(yq -r ".hub_postgres.users[${i}].password_secret" "${STACK_YML}" 2>/dev/null)
    grants=$(yq -r ".hub_postgres.users[${i}].grants[]? // empty" "${STACK_YML}" 2>/dev/null)

    if [[ -z "${username}" ]] || [[ "${username}" == "null" ]]; then
        continue
    fi

    printf "${BLUE}  User: %s${NC}\n" "${username}"

    # Resolve password from secrets
    password=""
    if [[ -n "${secret_name}" ]] && [[ "${secret_name}" != "null" ]]; then
        # Look up secret path in modules.yml
        secret_path=$(yq -r ".modules.${MODULE}.secrets_map.${secret_name} // empty" "${MODULES_YML}" 2>/dev/null)
        if [[ -n "${secret_path}" ]]; then
            full_path="${SPOKE_DIR}/${secret_path}"
            if [[ -f "${full_path}" ]]; then
                password=$(cat "${full_path}")
            else
                printf "${RED}    Secret file not found: %s${NC}\n" "${full_path}" >&2
                printf "${YELLOW}    Create the secret first: mkdir -p $(dirname "${full_path}") && openssl rand -base64 32 > ${full_path}${NC}\n" >&2
                continue
            fi
        else
            printf "${YELLOW}    Secret %s not mapped in modules.yml${NC}\n" "${secret_name}"
            continue
        fi
    fi

    # Create user if it doesn't exist
    user_exists=$(docker exec postgres-hub psql -U "${PGUSER}" -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname = '${username}';" 2>/dev/null || true)

    if [[ "${user_exists}" == "1" ]]; then
        printf "${GREEN}    User %s already exists${NC}\n" "${username}"
        # Update password if provided
        if [[ -n "${password}" ]]; then
            docker exec postgres-hub psql -U "${PGUSER}" -c \
                "ALTER USER ${username} WITH PASSWORD '${password}';" 2>/dev/null
            printf "${GREEN}    Updated password for %s${NC}\n" "${username}"
        fi
    else
        if [[ -n "${password}" ]]; then
            docker exec postgres-hub psql -U "${PGUSER}" -c \
                "CREATE USER ${username} WITH PASSWORD '${password}';" 2>/dev/null
        else
            docker exec postgres-hub psql -U "${PGUSER}" -c \
                "CREATE USER ${username};" 2>/dev/null
        fi
        printf "${GREEN}    Created user: %s${NC}\n" "${username}"
    fi

    # Apply grants
    for grant_db in ${grants}; do
        docker exec postgres-hub psql -U "${PGUSER}" -c \
            "GRANT ALL PRIVILEGES ON DATABASE ${grant_db} TO ${username};" 2>/dev/null
        docker exec postgres-hub psql -U "${PGUSER}" -d "${grant_db}" -c \
            "GRANT ALL ON SCHEMA public TO ${username};" 2>/dev/null
        printf "${GREEN}    Granted privileges on %s to %s${NC}\n" "${grant_db}" "${username}"
    done
done

printf "${GREEN}Hub postgres provisioning complete for %s${NC}\n" "${MODULE}"
