#!/usr/bin/env bash
# One-command setup script for the lead generation pipeline.
# Usage: bash scripts/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 1. Check prerequisites ────────────────────────────────────────────────────
info "Checking prerequisites..."

if ! command -v docker &>/dev/null; then
  error "Docker is not installed. Install it from https://docs.docker.com/get-docker/ and re-run this script."
fi

if ! docker compose version &>/dev/null 2>&1 && ! docker-compose version &>/dev/null 2>&1; then
  error "Docker Compose is not installed. Install it from https://docs.docker.com/compose/install/ and re-run this script."
fi

DOCKER_COMPOSE_CMD="docker compose"
if ! docker compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
fi

info "Docker: $(docker --version)"
info "Docker Compose: $($DOCKER_COMPOSE_CMD version --short 2>/dev/null || $DOCKER_COMPOSE_CMD version)"

# ── 2. Validate environment variables ─────────────────────────────────────────
info "Validating environment variables..."
bash "$SCRIPT_DIR/validate_env.sh"

# Load .env so we can use vars in this script
set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/.env"
set +a

# ── 3. Create required directories ────────────────────────────────────────────
info "Creating required host directories..."
mkdir -p /var/www/certbot
mkdir -p /etc/letsencrypt

# ── 4. Create Docker volumes ──────────────────────────────────────────────────
info "Creating Docker volumes..."
docker volume create lead_pipeline_n8n_data    2>/dev/null || true
docker volume create lead_pipeline_postgres_data 2>/dev/null || true

# ── 5. Start services ─────────────────────────────────────────────────────────
info "Starting services with Docker Compose..."
cd "$ROOT_DIR"
$DOCKER_COMPOSE_CMD up -d --pull always

# ── 6. Wait for n8n to initialize ─────────────────────────────────────────────
info "Waiting 20 seconds for n8n to initialize..."
sleep 20

# Check n8n is responding
MAX_RETRIES=10
RETRY=0
while [[ $RETRY -lt $MAX_RETRIES ]]; do
  if curl -sf "http://localhost:5678/healthz" &>/dev/null; then
    break
  fi
  RETRY=$((RETRY + 1))
  warn "n8n not ready yet (attempt $RETRY/$MAX_RETRIES), waiting 5 more seconds..."
  sleep 5
done

if [[ $RETRY -eq $MAX_RETRIES ]]; then
  warn "n8n health check timed out. It may still be starting — check 'docker logs lead_pipeline_n8n'."
fi

# ── 7. Print credentials and next steps ───────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Lead Pipeline Setup Complete"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  n8n URL (HTTP, pre-SSL):  http://${DOMAIN}:5678"
echo "  n8n Username:             ${N8N_USER}"
echo "  n8n Password:             ${N8N_PASSWORD}"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Next: Set up SSL with Let's Encrypt"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  Run the following command (replace with your email):"
echo ""
echo "  docker run --rm -it \\"
echo "    -v /etc/letsencrypt:/etc/letsencrypt \\"
echo "    -v /var/www/certbot:/var/www/certbot \\"
echo "    certbot/certbot certonly --webroot \\"
echo "    --webroot-path /var/www/certbot \\"
echo "    -d ${DOMAIN} \\"
echo "    --email you@yourdomain.com \\"
echo "    --agree-tos --no-eff-email"
echo ""
echo "  Then restart nginx:  docker restart lead_pipeline_nginx"
echo "  Then access n8n at:  https://${DOMAIN}"
echo ""
echo "  Import workflows from n8n/workflows/ via n8n UI:"
echo "    Settings → Import Workflow → select each .json file"
echo ""
