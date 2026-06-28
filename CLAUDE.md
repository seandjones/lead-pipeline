# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Automated B2B lead pipeline with two independent verticals:
- **Service Businesses** — scrapes Google Maps for HVAC/plumbing/roofing/etc. businesses, scores them with Claude for AI automation fit, enriches with Hunter.io + Apollo.io, pushes to HubSpot
- **Real Estate Agents** — targets agents who lack live chat and respond slowly to inquiries; fires email outreach if they don't reply within 15 minutes

**Stack:** n8n · Apify · Airtable · Hunter.io · Apollo.io · Claude API · HubSpot · SendGrid · Docker + Nginx

The only source code is `scraper/` (a Node.js/Puppeteer microservice). Everything else is n8n workflow JSON, shell scripts, and config.

## Common commands

```bash
# First-time setup (validates .env, starts all Docker services)
bash scripts/setup.sh

# Start/stop all services
docker compose up -d
docker compose down

# Build and start the Puppeteer scraper container
docker compose build scraper
docker compose up -d scraper

# Check running containers
docker ps | grep lead_pipeline

# View logs
docker logs lead_pipeline_n8n
docker logs lead_pipeline_nginx
docker logs lead_pipeline_scraper --tail=50

# Verify scraper is reachable from n8n's network
docker exec lead_pipeline_n8n wget -qO- http://scraper:3001/health

# Validate .env completeness
bash scripts/validate_env.sh

# Generate Apify input files and trigger scrape runs — service biz vertical
python3 scripts/generate_apify_inputs.py
bash scripts/trigger_apify_runs.sh          # also regenerates inputs
bash scripts/trigger_apify_runs.sh --skip-generate

# Generate and trigger — real estate vertical
python3 scripts/generate_re_apify_inputs.py
bash scripts/trigger_re_apify_runs.sh
bash scripts/trigger_re_apify_runs.sh --skip-generate

# Backup n8n data
bash scripts/backup_n8n.sh
```

## Architecture

### Data flow — service business vertical

```
Apify (Google Maps) → webhook/apify-webhook → Workflow A (ingest → Airtable Raw)
                                                      ↓ cron 6h
                                               Workflow B (fetch site → Claude score → Scored)
                                                      ↓ cron 4h
                                               Workflow C (Hunter + Apollo enrichment → HubSpot)
                                                      ↓ cron Sun 11:30pm
                                               Workflow D (archive stale → Slack report)
```

### Data flow — real estate vertical

```
Apify → webhook/re-apify-webhook → RE Workflow A (ingest → Agents Airtable Raw)
                                           ↓ cron 6h
                                    RE Workflow B (fetch site, detect chat, submit form → Audited)
                                           ↓ cron 15min
                                    RE Workflow C (response timer → email if no reply in 15min → Slow_Responder)
                                           ↓ cron 6h+30min
                                    RE Workflow D (Claude score)
                                           ↓ cron 4h
                                    RE Workflow E (Hunter + Apollo → HubSpot)
                                           ↓ cron Sun 11:30pm
                                    RE Workflow F (archive + weekly report)
```

### Docker services

| Container | Purpose |
|---|---|
| `lead_pipeline_n8n` | Workflow orchestration, exposed via Nginx |
| `lead_pipeline_postgres` | n8n persistence (workflows, credentials, execution history) |
| `lead_pipeline_scraper` | Puppeteer microservice at `http://scraper:3001` — internal network only |
| `lead_pipeline_nginx` | Reverse proxy + SSL termination |

### Scraper microservice (`scraper/`)

`POST /scrape { url }` → `{ html, finalUrl, error }` — launches Chromium, blocks images/fonts/media/stylesheets, renders JS, returns full HTML. Used by Workflow B as a fallback when a site has very little static HTML.

`GET /health` → `{ ok: true }` — used for readiness checks.

### Workflow files (`n8n/workflows/`)

Workflows are imported via n8n UI (Settings → Import Workflow). They are not executed from the CLI. Import order matters — always import in alphabetical order (A before B before C...).

**Active workflow for scoring:** `workflow_b_score_v2.json`. The older `workflow_b_score.json` and `workflow_b_score_updated.json` exist for reference — only v2 should be active. Running both simultaneously double-processes records.

### Airtable structure

Two separate Airtable bases:
- **`Lead Pipeline` base** (`AIRTABLE_BASE_ID`) — service business vertical; tables: `Leads`, `Pipeline_Errors`, `CRM_Retry_Queue`
- **`Real Estate Outreach` base** (`AIRTABLE_BASE_ID_RE`) — RE vertical; tables: `Agents`, `RE_Leads`

### API keys in n8n

All API keys are injected via `docker-compose.yml` environment variables and accessed inside n8n Function/Code nodes as `$env.VARIABLE_NAME`. Airtable and Apify credentials are also configured via n8n Credentials UI (HTTP Header Auth).

## Key gotchas

**`category` field must be Single line text, not Single select.** Airtable's Single select rejects unknown values; Google Maps returns free-form category strings that vary by vertical. Using Single select causes Workflow A ingestion failures logged to `Pipeline_Errors`.

**After changing `.env`, restart n8n** so it picks up new environment variables: `docker compose up -d n8n`.

**Scraper container RAM limit is 512 MB** (`mem_limit: 512m` in docker-compose.yml). On a 1 GB VPS, reduce to `256m` or `384m`. Puppeteer OOM kills appear in `docker logs lead_pipeline_scraper` as `Protocol error (Target.createTarget): Target closed.`

**CAN-SPAM compliance in RE Workflow C:** The outreach email footer with physical address and unsubscribe instructions is legally required. The opt-out webhook (`re-optout-webhook`) must be configured before activating Workflow C. Do not remove or modify the unsubscribe footer.

**RE reply matching is by email address.** If an agent replies from a different address than the one enriched by Hunter.io, `responded_at` won't auto-populate — update manually in Airtable.
