# ==============================================================================
# SPOKE HUB - CROWDSEC DOCKERFILE
# ==============================================================================
# Description: Custom CrowdSec build with non-root user configuration
# Author: Matt Barham
# Created: 2026-02-12
# Modified: 2026-04-22
# Version: 1.7.7-custom
# Host: Your Server
# ==============================================================================
# Type: Dockerfile
# Base Image: crowdsecurity/crowdsec:v1.7.7
# Component: spoke hub / service: crowdsec
# Security: non-root user, proper plugin permissions
# ==============================================================================

FROM crowdsecurity/crowdsec:v1.7.7

ARG USER_ID
ARG GROUP_ID
ARG USERNAME
ARG GROUPNAME

SHELL ["/bin/sh", "-c"]

USER root

# Create custom user and group
RUN addgroup --gid ${GROUP_ID} ${GROUPNAME} &&\
    adduser -D -H -G ${GROUPNAME} -u ${USER_ID} ${USERNAME} &&\
    install -d -m 0755 ${USERNAME} -g ${GROUPNAME} /home/${USERNAME}/ &&\
    mkdir /etc/${USERNAME}/

# Notification plugins are included in base image
RUN mkdir -p /usr/local/lib/crowdsec/plugins/ /etc/crowdsec/notifications/

# Fix ownership of all crowdsec directories and plugins
RUN chown -v --changes --silent --no-dereference --recursive \
        ${USER_ID}:${GROUP_ID} \
            /etc/${USERNAME}/ \
            /var/lib/${USERNAME}/data/ \
            /usr/local/lib/crowdsec/plugins/ \
            /etc/crowdsec/notifications/

# Ensure plugin executables are owned by the custom user
RUN find /usr/local/lib/crowdsec/plugins/ -type f -exec chown ${USER_ID}:${GROUP_ID} {} \; && \
    find /usr/local/lib/crowdsec/plugins/ -type f -exec chmod 755 {} \;

USER ${USERNAME}
