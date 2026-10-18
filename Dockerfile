# ghcr.io/actions/actions-runner:2.338.0 (multi-arch index digest, 2026-10-18).
# Dependabot bumps tag and digest together; review before rebuilding.
FROM ghcr.io/actions/actions-runner:2.338.0@sha256:4ffadc0002b2581327e06101fc8c06cd189232baf79fe561fac9caeb76f5e807

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl jq git gh just \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# TOOLCHAIN PLACEHOLDER: install your repo's build tools here, as root.
# Sudo is removed below, so jobs cannot install anything at runtime.
# Example:
# RUN apt-get update \
#     && apt-get install -y --no-install-recommends build-essential \
#     && rm -rf /var/lib/apt/lists/*
# ---------------------------------------------------------------------------

# Base image grants runner passwordless sudo; drop it so jobs cannot modify the image at runtime.
# SUDO_FORCE_REMOVE: sudo prerm aborts when root has no password.
RUN SUDO_FORCE_REMOVE=yes apt-get purge -y sudo \
    && rm -rf /etc/sudoers.d/* \
    && gpasswd -d runner sudo

# Separate chmod instead of COPY --chmod: works without BuildKit on older Docker.
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

USER runner
WORKDIR /home/runner
ENTRYPOINT ["/entrypoint.sh"]
