#!/usr/bin/env bash
# =============================================================================
# init-hermes.sh — First-time Hermes Agent initialization
# =============================================================================
# Run this ONCE on the Coolify server BEFORE deploying via Coolify.
# It creates the data directory, runs the interactive setup wizard,
# and writes the config files that the deployed container will use.
#
# Usage:
#   chmod +x init-hermes.sh
#   ./init-hermes.sh
#
# Or with a custom data path:
#   HERMES_DATA_PATH=/data/my-agent ./init-hermes.sh
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
HERMES_DATA_PATH="${HERMES_DATA_PATH:-/data/hermes}"
HERMES_IMAGE="nousresearch/hermes-agent:latest"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()     { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

# ── Checks ────────────────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || die "Docker is not installed or not in PATH"

info "Hermes Agent — first-time initialization"
echo ""
echo "  Data directory : ${HERMES_DATA_PATH}"
echo "  Docker image   : ${HERMES_IMAGE}"
echo ""

# ── Guard: already initialized? ───────────────────────────────────────────────
if [ -f "${HERMES_DATA_PATH}/.env" ]; then
    warn "Data directory already contains a .env file."
    warn "Hermes appears to be already initialized at: ${HERMES_DATA_PATH}"
    echo ""
    read -rp "Re-run the setup wizard anyway? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || { info "Aborted."; exit 0; }
fi

# ── Create data directory ─────────────────────────────────────────────────────
info "Creating data directory: ${HERMES_DATA_PATH}"
mkdir -p "${HERMES_DATA_PATH}"
success "Directory ready"

# ── Pull latest image ─────────────────────────────────────────────────────────
info "Pulling Hermes Agent image..."
docker pull "${HERMES_IMAGE}"
success "Image pulled"

# ── Run setup wizard ──────────────────────────────────────────────────────────
echo ""
info "Starting setup wizard (interactive)..."
info "This will prompt for your model provider and API key."
info "When asked about messaging platforms, you can skip — Hermes Desktop handles chat."
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

docker run --rm -it \
    -v "${HERMES_DATA_PATH}:/opt/data" \
    -e HERMES_UID="$(id -u)" \
    -e HERMES_GID="$(id -g)" \
    "${HERMES_IMAGE}" setup

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
success "Setup wizard complete"

# ── Verify output ─────────────────────────────────────────────────────────────
if [ ! -f "${HERMES_DATA_PATH}/.env" ]; then
    die "Expected ${HERMES_DATA_PATH}/.env was not created. Setup may have failed."
fi

success "Config written to ${HERMES_DATA_PATH}/.env"

# ── Reminder: API server key ──────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}IMPORTANT — API Server Key${NC}"
echo "To allow Hermes Desktop to connect, you must add API_SERVER_KEY"
echo "to the data .env file OR to Coolify's Environment Variables tab."
echo ""
echo "Generate a key with:"
echo "  openssl rand -hex 32"
echo ""
echo "Then add to ${HERMES_DATA_PATH}/.env:"
echo "  API_SERVER_KEY=<your-generated-key>"
echo "  API_SERVER_HOST=0.0.0.0"
echo ""

# ── Optional: inject API_SERVER_KEY now ───────────────────────────────────────
read -rp "Generate and inject API_SERVER_KEY now? [Y/n] " inject
if [[ "${inject,,}" != "n" ]]; then
    KEY=$(openssl rand -hex 32 2>/dev/null || cat /proc/sys/kernel/random/uuid | tr -d '-')
    echo "" >> "${HERMES_DATA_PATH}/.env"
    echo "# Added by init-hermes.sh — required for Hermes Desktop" >> "${HERMES_DATA_PATH}/.env"
    echo "API_SERVER_KEY=${KEY}" >> "${HERMES_DATA_PATH}/.env"
    echo "API_SERVER_HOST=0.0.0.0" >> "${HERMES_DATA_PATH}/.env"
    echo ""
    success "API_SERVER_KEY injected into ${HERMES_DATA_PATH}/.env"
    echo ""
    echo -e "${GREEN}Your API key (save this for Hermes Desktop):${NC}"
    echo ""
    echo -e "  ${CYAN}${KEY}${NC}"
    echo ""
    warn "Copy this key now — you won't see it again here."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
success "Initialization complete!"
echo ""
echo "Next steps:"
echo "  1. In Coolify → New Resource → Git (or Docker Compose)"
echo "  2. Point to this repo and select Dockerfile or docker-compose.coolify.yml"
echo "  3. Set volume: ${HERMES_DATA_PATH} → /opt/data"
echo "  4. Paste env vars from .env.example into Coolify's Environment tab"
echo "  5. Deploy"
echo "  6. In Hermes Desktop → Settings → Gateway:"
echo "       URL: https://hermes.alanwar.com"
echo "       Key: (the API_SERVER_KEY above)"
echo ""
