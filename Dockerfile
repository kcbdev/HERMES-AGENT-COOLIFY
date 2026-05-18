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

# ── System dependencies ──────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates \
        nodejs npm \
        python3 python3-pip python3-dev \
        gcc libffi-dev \
        ripgrep ffmpeg \
        gosu \
    && rm -rf /var/lib/apt/lists/*

# ── Clone hermes-agent from upstream ─────────────────────────────────────────
RUN git clone --depth=1 --branch "${HERMES_REF}" \
        https://github.com/NousResearch/hermes-agent /opt/hermes \
    || git clone --depth=1 \
        https://github.com/NousResearch/hermes-agent /opt/hermes

WORKDIR /opt/hermes

# ── Python package install ────────────────────────────────────────────────────
RUN pip install -e ".[all]" --break-system-packages --no-cache-dir

# ── Node dependencies (gateway web UI) ───────────────────────────────────────
RUN npm install --prefix /opt/hermes

# ── Playwright browsers ───────────────────────────────────────────────────────
RUN npx playwright install --with-deps chromium

# ── WhatsApp bridge ───────────────────────────────────────────────────────────
RUN if [ -d /opt/hermes/scripts/whatsapp-bridge ]; then \
        npm install --prefix /opt/hermes/scripts/whatsapp-bridge; \
    fi

# ── Entrypoint permissions ────────────────────────────────────────────────────
RUN chmod +x /opt/hermes/docker/entrypoint.sh

# ── Runtime config ────────────────────────────────────────────────────────────
ENV HERMES_HOME=/opt/data

# Data volume — all agent state lives here (config, memory, sessions, skills)
VOLUME ["/opt/data"]

# API server port (gateway)  |  Dashboard port
EXPOSE 8642 9119

ENTRYPOINT ["/opt/hermes/docker/entrypoint.sh"]

# Default command — override in Coolify if needed
CMD ["gateway", "run"]
