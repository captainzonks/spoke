# ==============================================================================
# SPOKE HUB - TRAEFIK DOCKERFILE
# ==============================================================================
# Description: Custom Traefik build with entrypoint/healthcheck scripts
# Author: Matt Barham
# Created: 2026-02-12
# Modified: 2026-04-23
# Version: 3.6.14-custom
# Host: Your Server
# ==============================================================================
# Type: Dockerfile
# Base Image: traefik:v3.6.14
# Component: spoke hub / service: traefik
# Security: non-root user execution, plugin readiness validation
# ==============================================================================
# Enhancements:
#   - traefik-entrypoint.sh: validates network, socket-proxy, CrowdSec before start
#   - traefik-healthcheck.sh: validates plugins loaded, not just API ping
#   - curl, netcat-openbsd: for connectivity checks
# ==============================================================================

FROM traefik:v3.6.14

ARG USER_ID
ARG GROUP_ID

ARG USERNAME
ARG GROUPNAME

SHELL ["/bin/sh", "-c"]

USER root

RUN apk add --no-cache curl netcat-openbsd

COPY traefik-entrypoint.sh /traefik-entrypoint.sh
COPY traefik-healthcheck.sh /traefik-healthcheck.sh
RUN chmod 755 /traefik-entrypoint.sh
RUN chmod 755 /traefik-healthcheck.sh
RUN chmod 755 /entrypoint.sh
RUN chmod 755 /usr/local/bin/traefik

RUN addgroup --gid ${GROUP_ID} ${GROUPNAME} &&\
    adduser -D -H -G ${GROUPNAME} -u ${USER_ID} ${USERNAME} &&\
    install -d -m 0755 -o ${USERNAME} -g ${GROUPNAME} /home/${USERNAME}/ &&\
    mkdir /etc/${USERNAME}/ &&\
    chown -v --changes --silent --no-dereference --recursive \
        ${USER_ID}:${GROUP_ID} \
            /etc/${USERNAME}/ \
            /traefik-entrypoint.sh \
            /traefik-healthcheck.sh

ENTRYPOINT ["/traefik-entrypoint.sh"]

USER ${USERNAME}
