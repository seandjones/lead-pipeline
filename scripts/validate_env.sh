#!/usr/bin/env bash
# Validates that all required environment variables are set and non-empty.
# Sourced by setup.sh; can also be run standalone: bash scripts/validate_env.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  echo "       Copy .env.example to .env and fill in your values."
  exit 1
fi

# Load .env
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

REQUIRED_VARS=(
  N8N_USER
  N8N_PASSWORD
  DOMAIN
  POSTGRES_DB
  POSTGRES_USER
  POSTGRES_PASSWORD
  WEBHOOK_SECRET
  APIFY_API_TOKEN
  AIRTABLE_API_KEY
  AIRTABLE_BASE_ID
  AIRTABLE_TABLE_NAME
  HUNTER_API_KEY
  ANTHROPIC_API_KEY
  HUBSPOT_API_KEY
)

OPTIONAL_VARS=(
  SLACK_WEBHOOK_URL
  TARGET_CITIES
  TARGET_VERTICALS
)

MISSING=()

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    MISSING+=("$var")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "ERROR: The following required environment variables are not set in .env:"
  for var in "${MISSING[@]}"; do
    echo "  - $var"
  done
  echo ""
  echo "Edit $ENV_FILE and set all required values before continuing."
  exit 1
fi

# Warn about empty optional vars
for var in "${OPTIONAL_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "WARN: Optional variable $var is not set — related features will be disabled."
  fi
done

echo "✓ All required environment variables are set."
