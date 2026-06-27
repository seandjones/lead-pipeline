#!/usr/bin/env bash
# Triggers Apify actor runs for all JSON files in scripts/re_apify_inputs/.
#
# Usage:
#   bash scripts/trigger_re_apify_runs.sh               # regenerate inputs, then trigger
#   bash scripts/trigger_re_apify_runs.sh --skip-generate  # trigger existing files as-is
#
# Apify actor used: compass/crawler-google-places
# This script is the RE vertical equivalent of trigger_apify_runs.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
INPUTS_DIR="$SCRIPT_DIR/re_apify_inputs"

SKIP_GENERATE=false
for arg in "$@"; do
  [[ "$arg" == "--skip-generate" ]] && SKIP_GENERATE=true
done

# Load .env
set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/.env"
set +a

if [[ "$SKIP_GENERATE" == false ]]; then
  echo "Generating RE Apify input files from TARGET_CITIES_RE..."
  python3 "$SCRIPT_DIR/generate_re_apify_inputs.py"
  echo ""
fi

ACTOR_ID="${APIFY_ACTOR_ID:-nwua9Gu5YkAVUScVsh}"

if [[ -z "${APIFY_API_TOKEN:-}" ]]; then
  echo "ERROR: APIFY_API_TOKEN is not set in .env"
  exit 1
fi

if [[ ! -d "$INPUTS_DIR" ]]; then
  echo "ERROR: RE Apify inputs directory not found: $INPUTS_DIR"
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

  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | RE | $filename | $run_id | $status" >> "$ROOT_DIR/apify_runs.log"

  if [[ "$run_id" != "UNKNOWN" && "$run_id" != "PARSE_ERROR" ]]; then
    echo "  Waiting 5 seconds before next run..."
    sleep 5
  fi
done

echo ""
echo "All RE runs triggered. Run log saved to: $ROOT_DIR/apify_runs.log"
echo ""
echo "When runs complete, Apify will POST results to your n8n webhook:"
echo "  https://${DOMAIN}/webhook/re-apify-webhook"
echo ""
echo "Configure this webhook in Apify Console:"
echo "  Actor run → Settings → Webhooks → Add webhook"
echo "  Event: ACTOR.RUN.SUCCEEDED"
echo "  URL:   https://${DOMAIN}/webhook/re-apify-webhook"
echo "  Header: X-Webhook-Secret: ${WEBHOOK_SECRET}"
