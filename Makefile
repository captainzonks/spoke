# ==============================================================================
# SPOKE - HUB-AND-SPOKE SERVER PLATFORM MAKEFILE
# ==============================================================================
# Description: Orchestrator for hub services and pluggable modules
# Author: Matt Barham
# Created: 2026-02-12
# Version: 1.0.0
# ==============================================================================

.DEFAULT_GOAL := help
SHELL := /bin/bash
export MAKEFLAGS += --no-print-directory

# Colors
export GREEN := \033[0;32m
export YELLOW := \033[1;33m
export BLUE := \033[0;34m
export RED := \033[0;31m
export NC := \033[0m

# Configuration
MAKEFILE_VERSION := 1.2.0
SPOKE_DIR ?= $(shell pwd)
export SPOKE_DIR
MODULES_DIR := $(SPOKE_DIR)/modules
HUB_DIR := $(SPOKE_DIR)/hub
SCRIPTS_DIR := $(SPOKE_DIR)/scripts/modules
TODAY_DATE := $(shell date --iso=date)

# CrowdSec: set to false for local testing, true for production
CROWDSEC_ENABLED ?= true
export CROWDSEC_ENABLED

# Hub compose files: include CrowdSec overlay and profile when enabled
# --profile crowdsec activates the profiled service so depends_on resolves
HUB_COMPOSE_FILES := -f $(HUB_DIR)/docker-compose.yml
ifeq ($(CROWDSEC_ENABLED),true)
  HUB_COMPOSE_FILES += -f $(HUB_DIR)/docker-compose.crowdsec.yml --profile crowdsec
endif

# Backward compatibility: STACK= aliases to MODULE=
ifdef STACK
MODULE := $(STACK)
endif

# Discover available modules (cloned repos with docker-compose.yml)
AVAILABLE_MODULES := $(shell find $(MODULES_DIR) -maxdepth 2 -name "docker-compose.yml" -exec dirname {} \; 2>/dev/null | xargs -I {} basename {} | sort | tr '\n' ' ')

#======================================
# HELP
#======================================

.PHONY: help
help: ## Show this help message
	@echo -e "$(BLUE)Spoke Server Platform ${MAKEFILE_VERSION}$(NC)"
	@echo -e "$(BLUE)============================================$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Hub Operations:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / && /Hub:/ {printf "  $(BLUE)%-25s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo -e "$(YELLOW)Module Operations:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / && /Module:/ {printf "  $(BLUE)%-25s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo -e "$(YELLOW)Bulk Operations:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / && /Bulk:/ {printf "  $(BLUE)%-25s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo -e "$(YELLOW)System Operations:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / && /System:/ {printf "  $(BLUE)%-25s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo -e "$(YELLOW)Examples:$(NC)"
	@echo -e "  $(BLUE)make hub-deploy$(NC)                          Deploy hub services"
	@echo -e "  $(BLUE)make deploy MODULE=monitoring$(NC)            Deploy monitoring module"
	@echo -e "  $(BLUE)make rebuild MODULE=plex SERVICE=plex$(NC)    Rebuild Plex service"
	@echo -e "  $(BLUE)make logs MODULE=monitoring SERVICE=grafana$(NC)"
	@echo -e "  $(BLUE)make deploy-all$(NC)                          Deploy hub + all modules"
	@echo ""
	@echo -e "$(YELLOW)Available Modules:$(NC) $(AVAILABLE_MODULES)"
	@echo ""
	@echo -e "$(YELLOW)Optional Variables:$(NC)"
	@echo -e "  $(BLUE)FORCE_REGEN=true$(NC)   Force .env regeneration"
	@echo -e "  $(BLUE)NO_CACHE=true$(NC)      Full rebuild without cache"
	@echo -e "  $(BLUE)SINCE=duration$(NC)     Filter logs (e.g., 1h, 30m)"

#======================================
# VALIDATION HELPERS
#======================================

validate-module:
	@if [ -z "$(MODULE)" ]; then \
		echo -e "$(RED)ERROR: MODULE parameter required$(NC)"; \
		echo -e "$(YELLOW)Usage: make <target> MODULE=<name> [SERVICE=<service>]$(NC)"; \
		echo -e "$(YELLOW)Available modules: $(AVAILABLE_MODULES)$(NC)"; \
		exit 1; \
	fi
	@if [ ! -d "$(MODULES_DIR)/$(MODULE)" ]; then \
		echo -e "$(RED)ERROR: Module directory not found: $(MODULES_DIR)/$(MODULE)$(NC)"; \
		echo -e "$(YELLOW)Run: make module-sync MODULE=$(MODULE)$(NC)"; \
		exit 1; \
	fi
	@if [ ! -f "$(MODULES_DIR)/$(MODULE)/docker-compose.yml" ]; then \
		echo -e "$(RED)ERROR: docker-compose.yml not found in $(MODULES_DIR)/$(MODULE)$(NC)"; \
		exit 1; \
	fi

validate-hub:
	@if [ ! -f "$(HUB_DIR)/docker-compose.yml" ]; then \
		echo -e "$(RED)ERROR: hub/docker-compose.yml not found$(NC)"; \
		exit 1; \
	fi

#======================================
# ENVIRONMENT GENERATION
#======================================

generate-hub-env:
	@echo -e "$(BLUE)Checking hub environment...$(NC)"
	@BASE_ENV="$(SPOKE_DIR)/shared/env/base.env"; \
	HUB_ENV="$(SPOKE_DIR)/shared/env/hub.env"; \
	TARGET_ENV="$(HUB_DIR)/.env"; \
	\
	if [ ! -f "$$BASE_ENV" ]; then \
		echo -e "$(RED)ERROR: Base env not found: $$BASE_ENV$(NC)"; \
		echo -e "$(YELLOW)Copy base.env.example to shared/env/base.env$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -f "$$HUB_ENV" ]; then \
		echo -e "$(RED)ERROR: Hub env not found: $$HUB_ENV$(NC)"; \
		echo -e "$(YELLOW)Copy hub.env.example to shared/env/hub.env$(NC)"; \
		exit 1; \
	fi; \
	\
	NEEDS_REGEN=false; \
	if [ ! -f "$$TARGET_ENV" ]; then \
		NEEDS_REGEN=true; \
	elif [ "$(FORCE_REGEN)" = "true" ]; then \
		NEEDS_REGEN=true; \
	elif [ "$$BASE_ENV" -nt "$$TARGET_ENV" ] || [ "$$HUB_ENV" -nt "$$TARGET_ENV" ]; then \
		NEEDS_REGEN=true; \
	fi; \
	\
	if [ "$$NEEDS_REGEN" = "true" ]; then \
		echo -e "$(BLUE)Generating hub .env...$(NC)"; \
		{ \
			echo "# Generated environment file for hub"; \
			echo "# Generated: $$(date -Iseconds)"; \
			echo "# DO NOT EDIT - Regenerated automatically"; \
			echo ""; \
			echo "BUILD_DATE=$(TODAY_DATE)"; \
			echo ""; \
			echo "# === BASE CONFIGURATION ==="; \
			cat "$$BASE_ENV"; \
			echo ""; \
			echo "# === HUB CONFIGURATION ==="; \
			cat "$$HUB_ENV"; \
		} > "$$TARGET_ENV"; \
		echo -e "$(GREEN)Hub environment generated$(NC)"; \
	else \
		echo -e "$(GREEN)Hub environment up to date$(NC)"; \
	fi

generate-module-env: validate-module
	@$(SCRIPTS_DIR)/generate_module_env.sh "$(MODULE)" $(if $(FORCE_REGEN),--force,)

#======================================
# SYSTEM OPERATIONS
#======================================

.PHONY: init
init: ## System: Initialize Spoke platform (auto-detect, directories, networks, config)
	@echo -e "$(BLUE)============================================$(NC)"
	@echo -e "$(BLUE)Spoke Platform Initialization$(NC)"
	@echo -e "$(BLUE)============================================$(NC)"
	@echo ""
	@# --- System Detection ---
	@echo -e "$(YELLOW)System Detection:$(NC)"
	@DETECTED_PUID=$$(id -u); \
	DETECTED_USERNAME=$$(whoami); \
	DETECTED_DGID=""; \
	if command -v getent &>/dev/null; then \
		DETECTED_DGID=$$(getent group docker 2>/dev/null | cut -d: -f3); \
	fi; \
	if [ -z "$$DETECTED_DGID" ]; then \
		echo -e "  $(RED)WARNING: docker group not found$(NC)"; \
		echo -e "  $(RED)  Run: sudo groupadd docker && sudo usermod -aG docker $$DETECTED_USERNAME$(NC)"; \
		echo -e "  $(RED)  Then log out and back in$(NC)"; \
	else \
		echo -e "  $(GREEN)Detected: PUID=$$DETECTED_PUID, DGID=$$DETECTED_DGID (docker group), USERNAME=$$DETECTED_USERNAME$(NC)"; \
	fi; \
	if ! id -nG | grep -qw docker; then \
		echo -e "  $(RED)WARNING: $$DETECTED_USERNAME is NOT in the docker group$(NC)"; \
		echo -e "  $(RED)  socket-proxy requires docker group access to /var/run/docker.sock$(NC)"; \
		echo -e "  $(RED)  Run: sudo usermod -aG docker $$DETECTED_USERNAME$(NC)"; \
	else \
		echo -e "  $(GREEN)User $$DETECTED_USERNAME is in docker group$(NC)"; \
	fi
	@echo ""
	@# --- Directory Structure ---
	@echo -e "$(YELLOW)Creating directory structure...$(NC)"
	@mkdir -p "$(SPOKE_DIR)/shared/env" && \
		echo -e "  $(GREEN)shared/env/$(NC)"
	@mkdir -p "$(SPOKE_DIR)/secrets/postgres" \
		"$(SPOKE_DIR)/secrets/authentik" \
		"$(SPOKE_DIR)/secrets/crowdsec" \
		"$(SPOKE_DIR)/secrets/tls" && \
		echo -e "  $(GREEN)secrets/{postgres,authentik,crowdsec,tls}/$(NC)"
	@mkdir -p "$(SPOKE_DIR)/appdata/traefik/rules" \
		"$(SPOKE_DIR)/appdata/traefik/plugins-storage" && \
		echo -e "  $(GREEN)appdata/traefik/{rules,plugins-storage}/$(NC)"
	@mkdir -p "$(SPOKE_DIR)/appdata/crowdsec" && \
		echo -e "  $(GREEN)appdata/crowdsec/$(NC)"
	@mkdir -p "$(SPOKE_DIR)/appdata/authentik" && \
		echo -e "  $(GREEN)appdata/authentik/$(NC)"
	@mkdir -p "$(SPOKE_DIR)/modules" && \
		echo -e "  $(GREEN)modules/$(NC)"
	@echo ""
	@# --- Copy Example Files ---
	@echo -e "$(YELLOW)Configuration files:$(NC)"
	@if [ ! -f "$(SPOKE_DIR)/shared/env/base.env" ]; then \
		cp "$(SPOKE_DIR)/base.env.example" "$(SPOKE_DIR)/shared/env/base.env"; \
		echo -e "  $(GREEN)Copied: base.env.example -> shared/env/base.env$(NC)"; \
	else \
		echo -e "  $(GREEN)base.env: already exists$(NC)"; \
	fi
	@if [ ! -f "$(SPOKE_DIR)/shared/env/hub.env" ]; then \
		cp "$(SPOKE_DIR)/hub.env.example" "$(SPOKE_DIR)/shared/env/hub.env"; \
		echo -e "  $(GREEN)Copied: hub.env.example -> shared/env/hub.env$(NC)"; \
	else \
		echo -e "  $(GREEN)hub.env: already exists$(NC)"; \
	fi
	@if [ ! -f "$(SPOKE_DIR)/modules.yml" ]; then \
		cp "$(SPOKE_DIR)/modules.yml.example" "$(SPOKE_DIR)/modules.yml"; \
		echo -e "  $(GREEN)Copied: modules.yml.example -> modules.yml$(NC)"; \
	else \
		echo -e "  $(GREEN)modules.yml: already exists$(NC)"; \
	fi
	@echo -e "  $(YELLOW)Remember to edit these files with your site-specific values$(NC)"
	@echo ""
	@# --- Docker Networks ---
	@echo -e "$(YELLOW)Docker networks:$(NC)"
	@docker network create --driver bridge --subnet 192.168.33.0/24 soxy 2>/dev/null && \
		echo -e "  $(GREEN)Created: soxy (192.168.33.0/24)$(NC)" || \
		echo -e "  $(GREEN)Exists: soxy$(NC)"
	@docker network create --driver bridge --subnet 192.168.35.0/24 troxy 2>/dev/null && \
		echo -e "  $(GREEN)Created: troxy (192.168.35.0/24)$(NC)" || \
		echo -e "  $(GREEN)Exists: troxy$(NC)"
	@docker network create --driver bridge --subnet 192.168.38.0/24 auxy 2>/dev/null && \
		echo -e "  $(GREEN)Created: auxy (192.168.38.0/24)$(NC)" || \
		echo -e "  $(GREEN)Exists: auxy$(NC)"
	@echo ""
	@# --- Required Secrets ---
	@echo -e "$(YELLOW)Required secrets (create these files with your values):$(NC)"
	@echo -e "  $(BLUE)secrets/postgres/postgres_password$(NC)"
	@echo -e "  $(BLUE)secrets/postgres/authentik_psql_password$(NC)"
	@echo -e "  $(BLUE)secrets/authentik/authentik_secret_key$(NC)"
	@echo -e "  $(BLUE)secrets/crowdsec/crowdsec_lapi_key$(NC)"
	@echo -e "  $(BLUE)secrets/crowdsec/crowdsec_online_api_login$(NC)"
	@echo -e "  $(BLUE)secrets/crowdsec/crowdsec_online_api_password$(NC)"
	@echo -e "  $(BLUE)secrets/tls/domain_1.pem$(NC)                (TLS certificate)"
	@echo -e "  $(BLUE)secrets/tls/domain_1.key$(NC)                (TLS private key)"
	@echo ""
	@echo -e "$(YELLOW)Optional secrets:$(NC)"
	@echo -e "  $(BLUE)secrets/basic_auth_credentials$(NC)            (for basic-auth middleware)"
	@echo ""
	@# --- Check for missing secrets ---
	@MISSING=0; \
	for f in \
		"$(SPOKE_DIR)/secrets/postgres/postgres_password" \
		"$(SPOKE_DIR)/secrets/postgres/authentik_psql_password" \
		"$(SPOKE_DIR)/secrets/authentik/authentik_secret_key" \
		"$(SPOKE_DIR)/secrets/crowdsec/crowdsec_lapi_key" \
		"$(SPOKE_DIR)/secrets/crowdsec/crowdsec_online_api_login" \
		"$(SPOKE_DIR)/secrets/crowdsec/crowdsec_online_api_password" \
		"$(SPOKE_DIR)/secrets/tls/domain_1.pem" \
		"$(SPOKE_DIR)/secrets/tls/domain_1.key"; \
	do \
		if [ ! -f "$$f" ]; then \
			MISSING=$$((MISSING + 1)); \
		fi; \
	done; \
	if [ "$$MISSING" -gt 0 ]; then \
		echo -e "$(RED)$$MISSING required secret(s) not yet created$(NC)"; \
	else \
		echo -e "$(GREEN)All required secrets present$(NC)"; \
	fi
	@echo ""
	@echo -e "$(GREEN)============================================$(NC)"
	@echo -e "$(GREEN)Initialization complete$(NC)"
	@echo -e "$(GREEN)============================================$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Next steps:$(NC)"
	@echo -e "  1. Edit $(BLUE)shared/env/base.env$(NC) — set PUID, DGID, DOMAIN, SPOKE_DIR, etc."
	@echo -e "  2. Edit $(BLUE)shared/env/hub.env$(NC) — verify versions and IPs"
	@echo -e "  3. Create all required secret files listed above"
	@echo -e "  4. Run $(BLUE)make hub-deploy$(NC) to start hub services"

.PHONY: init-local
init-local: ## System: Initialize for local testing (spoke.local domain, no CrowdSec required)
	@echo -e "$(BLUE)============================================$(NC)"
	@echo -e "$(BLUE)Spoke Local Initialization$(NC)"
	@echo -e "$(BLUE)============================================$(NC)"
	@echo ""
	@# --- System Detection ---
	@echo -e "$(YELLOW)System Detection:$(NC)"
	@DETECTED_PUID=$$(id -u); \
	DETECTED_USERNAME=$$(whoami); \
	DETECTED_DGID=""; \
	if command -v getent &>/dev/null; then \
		DETECTED_DGID=$$(getent group docker 2>/dev/null | cut -d: -f3); \
	fi; \
	if [ -z "$$DETECTED_DGID" ]; then \
		echo -e "  $(RED)WARNING: docker group not found$(NC)"; \
		echo -e "  $(RED)  Run: sudo groupadd docker && sudo usermod -aG docker $$DETECTED_USERNAME$(NC)"; \
	else \
		echo -e "  $(GREEN)Detected: PUID=$$DETECTED_PUID, DGID=$$DETECTED_DGID (docker group), USERNAME=$$DETECTED_USERNAME$(NC)"; \
	fi; \
	if ! id -nG | grep -qw docker; then \
		echo -e "  $(RED)WARNING: $$DETECTED_USERNAME is NOT in the docker group$(NC)"; \
	else \
		echo -e "  $(GREEN)User $$DETECTED_USERNAME is in docker group$(NC)"; \
	fi
	@echo ""
	@# --- Directory Structure ---
	@echo -e "$(YELLOW)Creating directory structure...$(NC)"
	@mkdir -p "$(SPOKE_DIR)/shared/env" && \
		echo -e "  $(GREEN)shared/env/$(NC)"
	@mkdir -p "$(SPOKE_DIR)/secrets/postgres" \
		"$(SPOKE_DIR)/secrets/authentik" \
		"$(SPOKE_DIR)/secrets/crowdsec" \
		"$(SPOKE_DIR)/secrets/traefik" \
		"$(SPOKE_DIR)/secrets/tls" && \
		echo -e "  $(GREEN)secrets/{postgres,authentik,crowdsec,traefik,tls}/$(NC)"
	@mkdir -p "$(SPOKE_DIR)/appdata/traefik/rules" \
		"$(SPOKE_DIR)/appdata/traefik/plugins-storage" && \
		echo -e "  $(GREEN)appdata/traefik/{rules,plugins-storage}/$(NC)"
	@mkdir -p "$(SPOKE_DIR)/appdata/crowdsec" && \
		echo -e "  $(GREEN)appdata/crowdsec/$(NC)"
	@mkdir -p "$(SPOKE_DIR)/appdata/authentik" && \
		echo -e "  $(GREEN)appdata/authentik/$(NC)"
	@mkdir -p "$(SPOKE_DIR)/modules" && \
		echo -e "  $(GREEN)modules/$(NC)"
	@echo ""
	@# --- Copy and Configure Example Files ---
	@echo -e "$(YELLOW)Configuration files:$(NC)"
	@BASE_ENV="$(SPOKE_DIR)/shared/env/base.env"; \
	if [ ! -f "$$BASE_ENV" ]; then \
		cp "$(SPOKE_DIR)/base.env.example" "$$BASE_ENV"; \
		sed -i 's|^DOMAIN=.*|DOMAIN=spoke.local|' "$$BASE_ENV"; \
		sed -i 's|^CDN_IPS=.*|CDN_IPS=|' "$$BASE_ENV"; \
		sed -i "s|^SPOKE_DIR=.*|SPOKE_DIR=$(SPOKE_DIR)|" "$$BASE_ENV"; \
		PUID=$$(id -u); DGID=$$(getent group docker 2>/dev/null | cut -d: -f3 || echo 999); USER=$$(whoami); \
		sed -i "s|^PUID=.*|PUID=$$PUID|" "$$BASE_ENV"; \
		sed -i "s|^DGID=.*|DGID=$$DGID|" "$$BASE_ENV"; \
		sed -i "s|^USERNAME=.*|USERNAME=$$USER|" "$$BASE_ENV"; \
		echo -e "  $(GREEN)Created: shared/env/base.env (DOMAIN=spoke.local, CDN_IPS=)$(NC)"; \
	else \
		echo -e "  $(YELLOW)base.env: already exists — not modified$(NC)"; \
	fi
	@HUB_ENV="$(SPOKE_DIR)/shared/env/hub.env"; \
	if [ ! -f "$$HUB_ENV" ]; then \
		cp "$(SPOKE_DIR)/hub.env.example" "$$HUB_ENV"; \
		sed -i 's|^CROWDSEC_ENABLED=.*|CROWDSEC_ENABLED=false|' "$$HUB_ENV"; \
		echo -e "  $(GREEN)Created: shared/env/hub.env (CROWDSEC_ENABLED=false)$(NC)"; \
	else \
		echo -e "  $(YELLOW)hub.env: already exists — not modified$(NC)"; \
	fi
	@if [ ! -f "$(SPOKE_DIR)/modules.yml" ]; then \
		cp "$(SPOKE_DIR)/modules.yml.example" "$(SPOKE_DIR)/modules.yml"; \
		sed -i 's|^  domain:.*|  domain: spoke.local|' "$(SPOKE_DIR)/modules.yml"; \
		echo -e "  $(GREEN)Copied: modules.yml.example -> modules.yml$(NC)"; \
	else \
		echo -e "  $(YELLOW)modules.yml: already exists — not modified$(NC)"; \
	fi
	@echo ""
	@# --- Docker Networks ---
	@echo -e "$(YELLOW)Docker networks:$(NC)"
	@docker network create --driver bridge --subnet 192.168.33.0/24 soxy 2>/dev/null && \
		echo -e "  $(GREEN)Created: soxy (192.168.33.0/24)$(NC)" || \
		echo -e "  $(GREEN)Exists: soxy$(NC)"
	@docker network create --driver bridge --subnet 192.168.35.0/24 troxy 2>/dev/null && \
		echo -e "  $(GREEN)Created: troxy (192.168.35.0/24)$(NC)" || \
		echo -e "  $(GREEN)Exists: troxy$(NC)"
	@docker network create --driver bridge --subnet 192.168.38.0/24 auxy 2>/dev/null && \
		echo -e "  $(GREEN)Created: auxy (192.168.38.0/24)$(NC)" || \
		echo -e "  $(GREEN)Exists: auxy$(NC)"
	@echo ""
	@# --- Generate Secrets ---
	@echo -e "$(YELLOW)Generating secrets...$(NC)"
	@SECRETS="$(SPOKE_DIR)/secrets"; \
	for f in \
		"$$SECRETS/postgres/postgres_password" \
		"$$SECRETS/postgres/authentik_psql_password" \
		"$$SECRETS/authentik/authentik_secret_key"; \
	do \
		if [ ! -f "$$f" ]; then \
			BYTES=32; \
			if echo "$$f" | grep -q authentik_secret_key; then BYTES=64; fi; \
			openssl rand -hex $$BYTES > "$$f"; \
			echo -e "  $(GREEN)Generated: $$(basename $$f)$(NC)"; \
		else \
			echo -e "  $(YELLOW)Exists: $$(basename $$f)$(NC)"; \
		fi; \
	done; \
	for f in \
		"$$SECRETS/crowdsec/crowdsec_lapi_key" \
		"$$SECRETS/crowdsec/crowdsec_online_api_login" \
		"$$SECRETS/crowdsec/crowdsec_online_api_password" \
		"$$SECRETS/traefik/basic_auth_credentials" \
		"$$SECRETS/tls/origin_pull_ca.pem"; \
	do \
		if [ ! -f "$$f" ]; then \
			touch "$$f"; \
			echo -e "  $(GREEN)Created placeholder: $$(basename $$f)$(NC)"; \
		else \
			echo -e "  $(YELLOW)Exists: $$(basename $$f)$(NC)"; \
		fi; \
	done
	@echo ""
	@# --- Generate Self-Signed TLS Certificate ---
	@echo -e "$(YELLOW)TLS certificate:$(NC)"
	@SECRETS="$(SPOKE_DIR)/secrets"; \
	if [ ! -f "$$SECRETS/tls/domain_1.pem" ]; then \
		echo -e "  Generating self-signed wildcard cert for *.spoke.local..."; \
		openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
			-keyout "$$SECRETS/tls/domain_1.key" \
			-out "$$SECRETS/tls/domain_1.pem" \
			-subj "/CN=spoke.local" \
			-addext "subjectAltName=DNS:spoke.local,DNS:*.spoke.local" \
			2>/dev/null; \
		cp "$$SECRETS/tls/domain_1.pem" "$$SECRETS/tls/domain_2.pem"; \
		cp "$$SECRETS/tls/domain_1.key" "$$SECRETS/tls/domain_2.key"; \
		cp "$$SECRETS/tls/domain_1.pem" "$$SECRETS/tls/domain_3.pem"; \
		cp "$$SECRETS/tls/domain_1.key" "$$SECRETS/tls/domain_3.key"; \
		echo -e "  $(GREEN)Generated: domain_1/2/3 certs (self-signed, 10yr)$(NC)"; \
	else \
		echo -e "  $(YELLOW)Exists: domain_1.pem — not regenerated$(NC)"; \
	fi
	@echo ""
	@echo -e "$(GREEN)============================================$(NC)"
	@echo -e "$(GREEN)Local initialization complete$(NC)"
	@echo -e "$(GREEN)============================================$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Next steps:$(NC)"
	@echo -e "  1. Add to /etc/hosts:"
	@echo -e "     $(BLUE)echo \"127.0.0.1 spoke.local *.spoke.local\" | sudo tee -a /etc/hosts$(NC)"
	@echo -e "  2. (Optional) Install mkcert for browser-trusted HTTPS:"
	@echo -e "     $(BLUE)mkcert -install$(NC)"
	@echo -e "     $(BLUE)mkcert -cert-file secrets/tls/domain_1.pem -key-file secrets/tls/domain_1.key \"*.spoke.local\"$(NC)"
	@echo -e "     $(BLUE)cp secrets/tls/domain_1.pem secrets/tls/domain_2.pem && cp secrets/tls/domain_1.key secrets/tls/domain_2.key$(NC)"
	@echo -e "     $(BLUE)cp secrets/tls/domain_1.pem secrets/tls/domain_3.pem && cp secrets/tls/domain_1.key secrets/tls/domain_3.key$(NC)"
	@echo -e "  3. Review $(BLUE)shared/env/base.env$(NC) — update PUID, DGID, TZ if needed"
	@echo -e "  4. Deploy: $(BLUE)make hub-deploy CROWDSEC_ENABLED=false$(NC)"
	@echo -e "  5. Access Authentik: $(BLUE)https://auth.spoke.local$(NC)"
	@echo ""
	@echo -e "  See $(BLUE)docs/crowdsec.md$(NC) to enable CrowdSec for production use."

#======================================
# HUB OPERATIONS
#======================================

.PHONY: hub-deploy
hub-deploy: validate-hub generate-hub-env ## Hub: Deploy hub services (SERVICE=name)
	@$(SCRIPTS_DIR)/deploy_hub_rules.sh
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Deploying $(SERVICE) in hub...$(NC)"; \
		docker compose $(HUB_COMPOSE_FILES) up -d $(SERVICE); \
	else \
		echo -e "$(YELLOW)Deploying hub services...$(NC)"; \
		docker compose $(HUB_COMPOSE_FILES) up -d; \
	fi
	@echo -e "$(GREEN)Hub deployed$(NC)"

.PHONY: hub-rebuild
hub-rebuild: validate-hub generate-hub-env ## Hub: Rebuild hub services (NO_CACHE=true for full rebuild)
	@CACHE_FLAG=""; \
	if [ "$(NO_CACHE)" = "true" ]; then \
		CACHE_FLAG="--no-cache"; \
	fi; \
	echo -e "$(YELLOW)Rebuilding hub services...$(NC)"; \
	docker compose $(HUB_COMPOSE_FILES) build $$CACHE_FLAG && \
	docker compose $(HUB_COMPOSE_FILES) up -d --force-recreate
	@echo -e "$(GREEN)Hub rebuild complete$(NC)"

.PHONY: hub-recreate
hub-recreate: validate-hub generate-hub-env ## Hub: Recreate hub without rebuild (SERVICE=name)
	@$(SCRIPTS_DIR)/deploy_hub_rules.sh
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Recreating $(SERVICE) in hub...$(NC)"; \
		docker compose $(HUB_COMPOSE_FILES) up -d --force-recreate $(SERVICE); \
	else \
		echo -e "$(YELLOW)Recreating all hub services...$(NC)"; \
		docker compose $(HUB_COMPOSE_FILES) up -d --force-recreate; \
	fi
	@echo -e "$(GREEN)Hub recreation complete$(NC)"

.PHONY: hub-restart
hub-restart: validate-hub ## Hub: Restart hub services (SERVICE=name)
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Restarting $(SERVICE) in hub...$(NC)"; \
		docker compose $(HUB_COMPOSE_FILES) restart $(SERVICE); \
	else \
		echo -e "$(YELLOW)Restarting all hub services...$(NC)"; \
		docker compose $(HUB_COMPOSE_FILES) restart; \
	fi
	@echo -e "$(GREEN)Hub restart complete$(NC)"

.PHONY: hub-health
hub-health: validate-hub ## Hub: Check hub service health
	@echo -e "$(YELLOW)Hub service health:$(NC)"
	@docker compose $(HUB_COMPOSE_FILES) ps
	@echo ""
	@echo -e "$(BLUE)Recent hub logs:$(NC)"
	@docker compose $(HUB_COMPOSE_FILES) logs --tail=5

.PHONY: hub-logs
hub-logs: validate-hub ## Hub: Show hub logs (SERVICE=name, SINCE=duration)
	@SINCE_FLAG=""; \
	if [ -n "$(SINCE)" ]; then \
		SINCE_FLAG="--since $(SINCE)"; \
	fi; \
	if [ -n "$(SERVICE)" ]; then \
		docker compose $(HUB_COMPOSE_FILES) logs $$SINCE_FLAG -f $(SERVICE); \
	else \
		docker compose $(HUB_COMPOSE_FILES) logs $$SINCE_FLAG -f; \
	fi

.PHONY: hub-stop
hub-stop: validate-hub ## Hub: Stop hub services (SERVICE=name)
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Stopping $(SERVICE) in hub...$(NC)"; \
		docker compose $(HUB_COMPOSE_FILES) stop $(SERVICE); \
	else \
		echo -e "$(YELLOW)Stopping hub services...$(NC)"; \
		docker compose $(HUB_COMPOSE_FILES) stop; \
	fi
	@echo -e "$(GREEN)Hub stopped$(NC)"

.PHONY: hub-down
hub-down: validate-hub ## Hub: Stop and remove hub services (SERVICE=name)
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Removing $(SERVICE) in hub...$(NC)"; \
		docker compose $(HUB_COMPOSE_FILES) down $(SERVICE); \
	else \
		echo -e "$(YELLOW)Stopping and removing hub services...$(NC)"; \
		docker compose $(HUB_COMPOSE_FILES) down; \
	fi
	@echo -e "$(GREEN)Hub removed$(NC)"

#======================================
# MODULE OPERATIONS
#======================================

.PHONY: module-sync
module-sync: ## Module: Clone/pull module repos (MODULE=name or all)
	@if [ -n "$(MODULE)" ]; then \
		$(SCRIPTS_DIR)/sync_modules.sh "$(MODULE)"; \
	else \
		$(SCRIPTS_DIR)/sync_modules.sh; \
	fi

.PHONY: validate
validate: validate-module ## Module: Validate module prerequisites (MODULE=name)
	@$(SCRIPTS_DIR)/validate_module.sh "$(MODULE)"

.PHONY: provision-db
provision-db: validate-module ## Module: Provision hub postgres databases/users (MODULE=name)
	@$(SCRIPTS_DIR)/provision_hub_postgres.sh "$(MODULE)"

.PHONY: deploy
deploy: validate-module generate-module-env ## Module: Deploy module (MODULE=name [SERVICE=name])
	@$(SCRIPTS_DIR)/validate_module.sh "$(MODULE)" --post-env
	@$(SCRIPTS_DIR)/provision_hub_postgres.sh "$(MODULE)" || true
	@$(SCRIPTS_DIR)/deploy_traefik_rules.sh "$(MODULE)" || true
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Deploying service $(SERVICE) in $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose up -d $(SERVICE); \
	else \
		echo -e "$(YELLOW)Deploying $(MODULE) module...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose up -d; \
	fi
	@echo -e "$(GREEN)Deployment complete$(NC)"

.PHONY: rebuild
rebuild: validate-module generate-module-env ## Module: Rebuild module (MODULE=name [SERVICE=name] [NO_CACHE=true])
	@$(SCRIPTS_DIR)/deploy_traefik_rules.sh "$(MODULE)" || true
	@CACHE_FLAG=""; \
	if [ "$(NO_CACHE)" = "true" ]; then \
		CACHE_FLAG="--no-cache"; \
	fi; \
	if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Rebuilding $(SERVICE) in $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && \
		docker compose build $$CACHE_FLAG $(SERVICE) && \
		docker compose up -d --force-recreate $(SERVICE); \
	else \
		echo -e "$(YELLOW)Rebuilding $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && \
		docker compose build $$CACHE_FLAG && \
		docker compose up -d --force-recreate; \
	fi
	@echo -e "$(GREEN)Rebuild complete$(NC)"

.PHONY: recreate
recreate: validate-module generate-module-env ## Module: Recreate without rebuild (MODULE=name [SERVICE=name])
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Recreating $(SERVICE) in $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose up -d --force-recreate $(SERVICE); \
	else \
		echo -e "$(YELLOW)Recreating $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose up -d --force-recreate; \
	fi
	@echo -e "$(GREEN)Recreation complete$(NC)"

.PHONY: stop
stop: validate-module ## Module: Stop module (MODULE=name [SERVICE=name])
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Stopping $(SERVICE) in $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose stop $(SERVICE); \
	else \
		echo -e "$(YELLOW)Stopping $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose stop; \
	fi
	@echo -e "$(GREEN)Stop complete$(NC)"

.PHONY: down
down: validate-module ## Module: Stop and remove module (MODULE=name [SERVICE=name])
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Removing $(SERVICE) in $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose down $(SERVICE); \
	else \
		echo -e "$(YELLOW)Removing $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose down; \
	fi
	@echo -e "$(GREEN)Module removed$(NC)"

.PHONY: restart
restart: validate-module ## Module: Restart module (MODULE=name [SERVICE=name])
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Restarting $(SERVICE) in $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose restart $(SERVICE); \
	else \
		echo -e "$(YELLOW)Restarting $(MODULE)...$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose restart; \
	fi
	@echo -e "$(GREEN)Restart complete$(NC)"

.PHONY: health
health: validate-module ## Module: Check module health (MODULE=name [SERVICE=name])
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(YELLOW)Health: $(SERVICE) in $(MODULE)$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose ps $(SERVICE) && \
		docker compose logs --tail=10 $(SERVICE); \
	else \
		echo -e "$(YELLOW)Health: $(MODULE)$(NC)"; \
		cd $(MODULES_DIR)/$(MODULE) && docker compose ps && \
		echo -e "$(BLUE)Recent logs:$(NC)" && \
		docker compose logs --tail=5; \
	fi

.PHONY: logs
logs: validate-module ## Module: Show logs (MODULE=name [SERVICE=name] [SINCE=duration])
	@SINCE_FLAG=""; \
	if [ -n "$(SINCE)" ]; then \
		SINCE_FLAG="--since $(SINCE)"; \
	fi; \
	if [ -n "$(SERVICE)" ]; then \
		cd $(MODULES_DIR)/$(MODULE) && docker compose logs $$SINCE_FLAG -f $(SERVICE); \
	else \
		cd $(MODULES_DIR)/$(MODULE) && docker compose logs $$SINCE_FLAG -f; \
	fi

#======================================
# BULK OPERATIONS
#======================================

.PHONY: deploy-all
deploy-all: ## Bulk: Deploy hub + all enabled modules
	@echo -e "$(YELLOW)Deploying hub + all modules...$(NC)"
	@$(MAKE) hub-deploy
	@echo ""
	@if command -v yq &>/dev/null && [ -f "$(SPOKE_DIR)/modules.yml" ]; then \
		for module in $$(yq -r '.modules | to_entries[] | select(.value.enabled == true) | .key' "$(SPOKE_DIR)/modules.yml"); do \
			if [ -d "$(MODULES_DIR)/$$module" ]; then \
				echo -e "$(BLUE)Deploying module: $$module$(NC)"; \
				$(MAKE) deploy MODULE=$$module || true; \
				echo ""; \
			else \
				echo -e "$(YELLOW)Skipping $$module (not synced, run: make module-sync MODULE=$$module)$(NC)"; \
			fi; \
		done; \
	else \
		for module in $(AVAILABLE_MODULES); do \
			echo -e "$(BLUE)Deploying module: $$module$(NC)"; \
			$(MAKE) deploy MODULE=$$module || true; \
			echo ""; \
		done; \
	fi
	@echo -e "$(GREEN)All deployments complete$(NC)"

.PHONY: health-all
health-all: ## Bulk: Health check hub + all modules
	@echo -e "$(YELLOW)=== Hub ===$(NC)"
	@$(MAKE) hub-health || true
	@echo ""
	@for module in $(AVAILABLE_MODULES); do \
		echo -e "$(YELLOW)=== $$module ===$(NC)"; \
		$(MAKE) health MODULE=$$module || true; \
		echo ""; \
	done

.PHONY: stop-all
stop-all: ## Bulk: Stop all modules then hub
	@echo -e "$(YELLOW)Stopping all modules...$(NC)"
	@for module in $(AVAILABLE_MODULES); do \
		echo -e "$(BLUE)Stopping $$module...$(NC)"; \
		$(MAKE) stop MODULE=$$module || true; \
	done
	@echo ""
	@echo -e "$(YELLOW)Stopping hub...$(NC)"
	@$(MAKE) hub-stop
	@echo -e "$(GREEN)All services stopped$(NC)"

#======================================
# SYSTEM
#======================================

.PHONY: status
status: ## System: Show status of all running Spoke containers
	@echo -e "$(BLUE)Spoke Platform Status$(NC)"
	@echo -e "$(BLUE)============================================$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Hub:$(NC)"
	@docker compose $(HUB_COMPOSE_FILES) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  (not running)"
	@echo ""
	@for module in $(AVAILABLE_MODULES); do \
		echo -e "$(YELLOW)$$module:$(NC)"; \
		cd $(MODULES_DIR)/$$module && docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  (not running)"; \
		echo ""; \
	done

.PHONY: log-analysis
log-analysis: ## System: Run AI log analysis (HOURS=N for lookback window, DRY_RUN=true to skip email)
	@$(SPOKE_DIR)/scripts/maintenance/spoke_log_analysis.sh \
		$(if $(HOURS),--hours $(HOURS)) \
		$(if $(filter true,$(DRY_RUN)),--dry-run)

.PHONY: clean-docker
clean-docker: ## System: Clean Docker resources (stopped containers, dangling images)
	@echo -e "$(YELLOW)This will remove stopped containers, dangling images, and unused networks$(NC)"
	@echo -e "$(RED)Press Enter to continue, Ctrl+C to cancel$(NC)"
	@read -r
	@docker system prune -f
	@echo -e "$(GREEN)Docker cleanup complete$(NC)"
