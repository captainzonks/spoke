# ==============================================================================
# SPOKE HUB - POSTGRES DOCKERFILE
# ==============================================================================
# Description: PostgreSQL with custom UID/GID for host filesystem permissions
# Author: Matt Barham
# Created: 2026-02-12
# Modified: 2026-04-22
# Version: 18.3-custom
# Host: Your Server
# ==============================================================================
# Type: Dockerfile
# Base Image: postgres:18.3
# Component: spoke hub / service: postgres-hub
# Security: custom user mapping (remaps from default 999:999)
# ==============================================================================

FROM postgres:18.3

ARG USER_ID
ARG GROUP_ID

ARG USERNAME
ARG GROUPNAME

ARG OG_UID
ARG OG_GID

SHELL ["/bin/sh", "-c"]

USER root

RUN if [ ${USER_ID:-0} -ne 0 ] && [ ${GROUP_ID:-0} -ne 0 ]; then\
    userdel -f ${USERNAME} &&\
    if getent group ${GROUPNAME}; then groupdel ${GROUPNAME}; fi &&\
    groupadd -g ${GROUP_ID} ${GROUPNAME} &&\
    useradd -l -u ${USER_ID} -g ${GROUPNAME} ${USERNAME} &&\
    install -d -m 0755 -o ${USERNAME} -g ${GROUPNAME} /home/${USERNAME}/ &&\
    chown --changes --silent --no-dereference --recursive \
        --from=${OG_UID}:${OG_GID} ${USER_ID}:${GROUP_ID} \
            /etc/postgresql/ \
            /var/lib/postgresql/ \
            /var/run/postgresql/ \
;fi

USER ${USERNAME}
