#!/usr/bin/env bash
# Triggers Apify actor runs for all JSON files in scripts/apify_inputs/.
# Usage: bash scripts/trigger_apify_runs.sh
#
# Apify actor used: compass/crawler-google-places
# Find actor ID in Apify Console → Actors → search "Google Maps Scraper" → copy Actor ID from URL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
INPUTS_DIR="$SCRIPT_DIR/apify_inputs"

# Load .env
set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/.env"
set +a

# Apify actor ID for "Google Maps Scraper" (compass/crawler-google-places)
# Verify this in your Apify console — actor IDs are stable but confirm before running.
ACTOR_ID="${APIFY_ACTOR_ID:-nwua9Gu5YkAVUScVsh}"

if [[ -z "${APIFY_API_TOKEN:-}" ]]; then
  echo "ERROR: APIFY_API_TOKEN is not set in .env"
  exit 1
fi

if [[ ! -d "$INPUTS_DIR" ]]; then
  echo "ERROR: Apify inputs directory not found: $INPUTS_DIR"
  exit 1
fi

INPUT_FILES=("$INPUTS_DIR"/*.json)
if [[ ${#INPUT_FILES[@]} -eq 0 ]] || [[ ! -f "${INPUT_FILES[0]}" ]]; then
  echo "ERROR: No JSON files found in $INPUTS_DIR"
  exit 1
fi

echo "Found ${#INPUT_FILES[@]} input file(s). Starting Apify runs..."
echo ""

for input_file in "${INPUT_FILES[@]}"; do
  filename=$(basename "$input_file")
  echo "─────────────────────────────────────────────"
  echo "Triggering run for: $filename"

  response=$(curl -sf \
    --request POST \
    --url "https://api.apify.com/v2/acts/${ACTOR_ID}/runs" \
    --header "Authorization: Bearer ${APIFY_API_TOKEN}" \
    --header "Content-Type: application/json" \
    --data @"$input_file" \
    2>&1) || {
      echo "  ERROR: curl failed for $filename"
      echo "  Response: $response"
      continue
    }

  run_id=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('id','UNKNOWN'))" 2>/dev/null || echo "PARSE_ERROR")
  status=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','UNKNOWN'))" 2>/dev/null || echo "PARSE_ERROR")

  echo "  Run ID: $run_id"
  echo "  Status: $status"
  echo "  View at: https://console.apify.com/actors/${ACTOR_ID}/runs/${run_id}"

  # Log run ID to file for traceability
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $filename | $run_id | $status" >> "$ROOT_DIR/apify_runs.log"

  if [[ "$run_id" != "UNKNOWN" && "$run_id" != "PARSE_ERROR" ]]; then
    echo "  Waiting 5 seconds before next run..."
    sleep 5
  fi
done

echo ""
echo "All runs triggered. Run log saved to: $ROOT_DIR/apify_runs.log"
echo ""
echo "When runs complete, Apify will POST results to your n8n webhook:"
echo "  https://${DOMAIN}/webhook/apify-webhook"
echo ""
echo "Configure this webhook in Apify Console:"
echo "  Actor run → Settings → Webhooks → Add webhook"
echo "  Event: ACTOR.RUN.SUCCEEDED"
echo "  URL:   https://${DOMAIN}/webhook/apify-webhook"
echo "  Header: X-Webhook-Secret: ${WEBHOOK_SECRET}"
