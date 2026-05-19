# =============================================================================
# Hermes Agent — Coolify Deployment Dockerfile
# =============================================================================
# Self-contained: clones hermes-agent from upstream at build time.
# Point Coolify at this repo — no separate source checkout needed.
#
# Build args:
#   HERMES_REF   — git ref to pin (branch, tag, or SHA). Default: main
#
# Usage (manual):
#   docker build --build-arg HERMES_REF=main -t hermes-agent .
#   docker run -d \
#     -v /data/hermes:/opt/data \
#     -p 8642:8642 \
#     -e API_SERVER_HOST=0.0.0.0 \
#     -e API_SERVER_KEY=changeme \
#     hermes-agent gateway run
# =============================================================================

FROM debian:bookworm-slim

ARG HERMES_REF=main

# ── Node.js 20 LTS (required by baileys@7) ──────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates \
        python3 python3-pip python3-dev python3-venv \
        gcc libffi-dev \
        ripgrep ffmpeg \
        gosu gnupg \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── hermes runtime user (matches upstream UID 10000) ──────────────────────────
RUN useradd -u 10000 -m -d /opt/data hermes

# ── Clone hermes-agent from upstream ─────────────────────────────────────────
RUN git clone --depth=1 --branch "${HERMES_REF}" \
        https://github.com/NousResearch/hermes-agent /opt/hermes \
    || git clone --depth=1 \
        https://github.com/NousResearch/hermes-agent /opt/hermes

WORKDIR /opt/hermes

# ── Create venv (matching upstream's .venv setup) ─────────────────────────────
RUN python3 -m venv /opt/hermes/.venv

# ── Python package install ────────────────────────────────────────────────────
RUN /opt/hermes/.venv/bin/pip install -e ".[all]" --break-system-packages --no-cache-dir

# ── Node dependencies (gateway web UI) ───────────────────────────────────────
RUN npm install --prefix /opt/hermes

# ── Build web UI for dashboard ─────────────────────────────────────────────────
RUN cd /opt/hermes/web && npm install && npm run build

# ── Playwright browsers ───────────────────────────────────────────────────────
RUN npx playwright install --with-deps chromium

# ── WhatsApp bridge ───────────────────────────────────────────────────────────
RUN if [ -d /opt/hermes/scripts/whatsapp-bridge ]; then \
        npm install --prefix /opt/hermes/scripts/whatsapp-bridge; \
    fi

# ── Fix ownership for hermes runtime user (matching upstream approach) ─────
# Make install dir world-readable so any HERMES_UID can read it at runtime.
# The .venv and node_modules need to be writable by hermes (for lazy_deps and runtime npm).
RUN chmod -R a+rX /opt/hermes \
    && chown -R hermes:hermes /opt/hermes/.venv /opt/hermes/node_modules \
    && chmod +x /opt/hermes/docker/entrypoint.sh

# ── Runtime config ────────────────────────────────────────────────────────────
ENV HERMES_HOME=/opt/data
ENV API_SERVER_ENABLED=true
ENV API_SERVER_HOST=0.0.0.0
ENV API_SERVER_PORT=8642

# Data volume — all agent state lives here (config, memory, sessions, skills)
VOLUME ["/opt/data"]

# API server port (gateway)  |  Dashboard port
EXPOSE 8642 9119

ENTRYPOINT ["/opt/hermes/docker/entrypoint.sh"]

# Default command — override in Coolify if needed
CMD ["gateway", "run"]
