# Lead Generation Pipeline

Automated lead pipeline for targeting small trades businesses (HVAC, plumbing, roofing) that are candidates for AI automation services.

**Stack:** n8n · Apify · Airtable · Hunter.io · Apollo.io · Claude API · HubSpot · Docker + Nginx

---

## Prerequisites

- A VPS with a public IP (Ubuntu 22.04 recommended, 2GB RAM minimum)
- A domain name pointed at that IP via an A record
- Docker Engine ≥ 24.x
- Docker Compose ≥ 2.x
- Accounts and API keys for: Apify, Airtable, Hunter.io, Apollo.io, Anthropic, HubSpot

---

## First-Time Setup

### 1. Clone and configure

```bash
git clone <your-repo-url> lead-pipeline
cd lead-pipeline
cp .env.example .env
nano .env   # Fill in every variable — see comments for where to get each key
```

### 2. Run the setup script

```bash
chmod +x scripts/*.sh
bash scripts/setup.sh
```

This will validate your `.env`, start all Docker services, and print your n8n URL and credentials.

### 3. Set up SSL (Let's Encrypt)

After `setup.sh` finishes it will print the exact `certbot` command to run. It looks like:

```bash
docker run --rm -it \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/www/certbot:/var/www/certbot \
  certbot/certbot certonly --webroot \
  --webroot-path /var/www/certbot \
  -d your.domain.com \
  --email you@yourdomain.com \
  --agree-tos --no-eff-email

docker restart lead_pipeline_nginx
```

### 4. Import workflows into n8n

1. Open `https://your.domain.com` and log in with your `N8N_USER` / `N8N_PASSWORD`
2. Go to **Settings → Import Workflow**
3. Import each file from `n8n/workflows/` in order:
   - `workflow_a_ingest.json`
   - `workflow_b_score.json`
   - `workflow_c_enrich_push.json`
   - `workflow_d_maintenance.json`

### 5. Configure n8n Credentials

In n8n UI go to **Credentials → Add Credential** and create:

| Credential Name | Type | Value |
|---|---|---|
| `Apify API Token` | HTTP Header Auth | Header: `Authorization`, Value: `Bearer YOUR_APIFY_TOKEN` |
| `Airtable API Key` | HTTP Header Auth | Header: `Authorization`, Value: `Bearer YOUR_AIRTABLE_KEY` |

All other API keys (Anthropic, HubSpot, Hunter, Apollo, Slack) are passed via environment variables and accessed in workflows via `$env.VARIABLE_NAME`.

### 6. Activate workflows

Open each workflow in n8n and toggle it to **Active**.

---

## Airtable Setup

### Creating the base

1. Go to [airtable.com](https://airtable.com) → **Add a base** → **Start from scratch**
2. Name it `Lead Pipeline`
3. Rename the default table to `Leads`
4. Add a second table named `Pipeline_Errors` (used for error logging)
5. Add a third table named `CRM_Retry_Queue` (used for HubSpot retry logic)

> **All three tables must exist before activating any workflow.** Workflow A writes to `Pipeline_Errors` on insert failures. Workflow C writes to `CRM_Retry_Queue` on HubSpot 5xx errors.

### Required fields in the `Pipeline_Errors` table

Created automatically when Workflow A catches an Airtable insert failure. Create this table manually with the following fields:

| Field Name | Field Type | Notes |
|---|---|---|
| `workflow` | Single line text | Primary field — which workflow logged the error |
| `error_message` | Long text | The error message from n8n |
| `raw_record` | Long text | First 500 chars of the record that failed |
| `timestamp` | Single line text | ISO timestamp of when the error occurred |

### Required fields in the `CRM_Retry_Queue` table

Used by Workflow C when HubSpot returns a 5xx server error. The record is queued here and retried on the next run.

| Field Name | Field Type | Notes |
|---|---|---|
| `business_name` | Single line text | Primary field |
| `airtable_record_id` | Single line text | The Airtable record ID to update after successful retry |
| `hubspot_payload` | Long text | JSON payload that failed — used to retry the push |
| `error_message` | Long text | The HubSpot error response |
| `retry_count` | Number | Integer — incremented each retry attempt |
| `status` | Single select | Options: Pending, Retried, Failed |
| `timestamp` | Single line text | ISO timestamp when the failure occurred |

### Getting your Base ID

Open your base in a browser. The URL looks like:
```
https://airtable.com/appXXXXXXXXXXXXXX/tblYYYYYYYYYYYYYY/...
```
Copy the `appXXXX...` portion — that is your `AIRTABLE_BASE_ID`.

### Required fields in the `Leads` table

Create these fields manually or via the Airtable API:

| Field Name | Field Type |
|---|---|
| `business_name` | Single line text (primary field — rename default) |
| `website` | URL |
| `domain` | Single line text |
| `phone` | Phone number |
| `address` | Single line text |
| `city` | Single line text |
| `state` | Single line text |
| `google_rating` | Number (precision: 1 decimal) |
| `review_count` | Number (integer) |
| `category` | Single line text |
| `has_website` | Checkbox |
| `source` | Single select: Maps, Indeed, Craigslist |
| `source_query` | Single line text |
| `ai_score` | Number (integer) |
| `ai_signals` | Long text |
| `ai_summary` | Long text |
| `website_fetch_status` | Single select: Pending, Success, Failed, No Website |
| `contact_email` | Email |
| `contact_name` | Single line text |
| `mobile_phone` | Phone number |
| `hubspot_contact_id` | Single line text |
| `status` | Single select: Raw, Scored, Enriched, Pushed, Archived, Duplicate |
| `date_added` | Date |
| `date_scored` | Date |
| `date_pushed` | Date |
| `apify_run_id` | Single line text |
| `notes` | Long text |

---

## HubSpot Setup

### Custom properties

Before running Workflow C, create these custom contact properties in HubSpot:

**HubSpot → Settings → Properties → Contact Properties → Create property**

| Label | Internal Name | Field Type |
|---|---|---|
| AI Automation Score | `ai_automation_score` | Number |
| Automation Pain Signals | `automation_pain_signals` | Multi-line text |
| Lead Summary | `lead_summary` | Multi-line text |
| Google Rating | `google_rating` | Number |
| Review Count | `review_count` | Number |
| Lead Source | `lead_source` | Single-line text |


### Custom deal property

Create one deal property:

| Label | Internal Name | Field Type |
|---|---|---|
| Lead Score | `lead_score` | Number |

### API key

Use a **Private App** token (not a legacy API key):
1. HubSpot → Settings → Integrations → Private Apps → Create a private app
2. Scopes required: `crm.objects.contacts.write`, `crm.objects.deals.write`, `crm.associations.write`
3. Copy the token and set it as `HUBSPOT_API_KEY` in `.env`

---

## Apollo.io Setup

Workflow C uses Apollo.io after Hunter.io to search for Owner/CEO contacts by company website, pulling a mobile phone number and name.

### Account and plan

- Sign up at [app.apollo.io](https://app.apollo.io)
- **A paid plan is required for mobile phone export.** The free tier returns emails only; the Basic plan ($49/mo) unlocks mobile numbers.
- Apollo's API credits are consumed per contact record revealed. Each lead that has a website will use one search credit and up to one export credit (for the mobile number).

### Get your API key

1. Log in to Apollo → click your avatar (bottom-left) → **Settings**
2. Go to **Integrations → API** (or navigate to **Developer Settings**)
3. Copy your API key and set it as `APOLLO_API_KEY` in `.env`

> Rate limits: the Basic plan allows 50 API requests/minute. Workflow C processes up to 15 leads per run every 4 hours, well within limits.

### How the search works

For each lead with a `website` value, Workflow C calls `POST https://api.apollo.io/v1/mixed_people/search` with:
- `q_organization_website_url` — the lead's website URL
- `person_titles` — `["owner", "ceo", "president"]`
- `per_page` — `5`

From the results, the workflow picks the highest-priority match (owner → ceo → president → first result) and extracts:
- **Mobile phone** → written to Airtable `mobile_phone` field (`type: "mobile"` preferred; falls back to first available number)
- **Contact name** → overwrites the Hunter.io name in `contact_name` (Apollo is more authoritative for business owners)

If Apollo returns an error or no results, the workflow continues without failing — `mobile_phone` is left blank and the Hunter.io name (if any) is preserved.

### Airtable field required

Add this field to your `Leads` table before activating the updated Workflow C:

| Field Name | Field Type |
|---|---|
| `mobile_phone` | Phone number |

---

## Apify Setup

### Which actor to use

Use **Google Maps Scraper** by Compass:
- Actor ID: `nwua9Gu5YkAVUScVsh` (verify in Apify Console)
- Or search "Google Maps Scraper" in the Apify Store

Set `APIFY_ACTOR_ID=nwua9Gu5YkAVUScVsh` in your `.env` (used by `trigger_apify_runs.sh`).

### Configure the webhook

After your first manual run:
1. In Apify Console, go to the actor → **Runs** → click the run → **Settings** tab
2. Or set at the actor level: Actor → **Settings** → **Webhooks**
3. Add webhook:
   - **Event:** `ACTOR.RUN.SUCCEEDED`
   - **URL:** `https://YOUR_DOMAIN/webhook/apify-webhook`
   - **HTTP Method:** POST
   - **Custom headers:** `X-Webhook-Secret: YOUR_WEBHOOK_SECRET`

---

## Running the First Scrape

### Option A: Trigger via script

```bash
bash scripts/trigger_apify_runs.sh
```

This fires all three Denver verticals (HVAC, plumbing, roofing) in sequence with a 5-second gap between runs.

### Option B: Manual run in Apify UI

1. Open Apify Console → Actors → Google Maps Scraper
2. Paste the contents of `scripts/apify_inputs/denver_hvac.json` as the actor input
3. Click **Start**
4. When the run completes, Apify fires the webhook → Workflow A triggers automatically

### Verify data is flowing

1. In n8n: go to **Executions** → Workflow A should show a recent execution
2. In Airtable: new records should appear in the `Leads` table with `status = Raw`
3. Workflow B runs every 6 hours and will pick up `Raw` records with `website_fetch_status = Pending`

---

## Calibrating the AI Score

After the first batch of 25 records are scored by Workflow B:

1. In Airtable, filter for `status = Scored` and sort by `ai_score` descending
2. Open the top 10 records and review `ai_signals` and `ai_summary`
3. Check a few of the actual websites manually to validate the score makes sense
4. If scoring is too generous (too many 7+ scores for businesses that don't need automation):
   - Open Workflow B in n8n → **Build Claude Prompt** node
   - Adjust the `HIGH-value targets` and `LOW-value targets` descriptions in the system prompt
   - Re-run: in Airtable, change a batch of `Scored` records back to `Raw` with `website_fetch_status = Pending`, then manually trigger Workflow B
5. If scoring is too strict (most scores are 1-3):
   - Loosen the `HIGH-value` criteria or reduce the penalty for not having software mentions

---

## Scaling to New Cities

1. Create a new input file in `scripts/apify_inputs/`:
   ```bash
   cp scripts/apify_inputs/denver_hvac.json scripts/apify_inputs/boulder_hvac.json
   ```
2. Edit the search strings to reference the new city
3. Run `bash scripts/trigger_apify_runs.sh` — it picks up all JSON files automatically
4. Or trigger individual files:
   ```bash
   curl -X POST https://api.apify.com/v2/acts/nwua9Gu5YkAVUScVsh/runs \
     -H "Authorization: Bearer $APIFY_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d @scripts/apify_inputs/boulder_hvac.json
   ```

---

## Monitoring

### n8n Execution Log

- **Settings → Executions** shows every workflow run with success/failure status
- Failed executions appear in red — click to see which node failed and the error message
- Workflow A executions are triggered by Apify webhooks — if you don't see them, the webhook isn't reaching n8n (check Nginx logs: `docker logs lead_pipeline_nginx`)

### Slack Alerts

If `SLACK_WEBHOOK_URL` is set, you will receive:
- ✅ Workflow A completion after each Apify webhook
- 📊 Workflow B completion after each scoring batch
- 🔧 Individual lead alerts from Workflow C for each pushed lead (includes mobile number if found via Apollo)
- 📊 Weekly summary from Workflow D every Sunday night
- 🚨 Error alerts from any workflow's Error Trigger

### Airtable as a dashboard

Filter and view:
- `status = Raw` → leads waiting to be scored
- `status = Scored` AND `ai_score >= 6` → leads ready for enrichment
- `status = Pushed` → closed loop, in HubSpot
- `ai_score = -1` → Claude API errors (check Anthropic console for quota issues)

---

## Troubleshooting

### 1. Workflow A never fires after Apify run completes

**Cause:** Webhook not reaching n8n.
- Check: `docker logs lead_pipeline_nginx` for 502 errors
- Check: n8n is running: `docker ps | grep n8n`
- Check: webhook URL in Apify matches `https://YOUR_DOMAIN/webhook/apify-webhook`
- Check: `X-Webhook-Secret` header value matches `WEBHOOK_SECRET` in `.env`
- Test manually: `curl -X POST https://YOUR_DOMAIN/webhook/apify-webhook -H "X-Webhook-Secret: YOUR_SECRET" -H "Content-Type: application/json" -d '{"eventType":"ACTOR.RUN.SUCCEEDED","resource":{"id":"test","defaultDatasetId":"test"}}'`

### 2. Workflow B scores everything as 0 or -1

**Cause:** Claude API key invalid, quota exceeded, or the website fetch is failing.
- Check `ai_signals` field — if it says `Claude API Error` or `Website fetch failed`, that's the cause
- Check Anthropic Console for usage and quota: [console.anthropic.com](https://console.anthropic.com)
- Verify `ANTHROPIC_API_KEY` in `.env` is correct and active

### 3. Airtable API returns 422 or 404

**Cause:** Field name mismatch between workflow and actual Airtable column names.
- Field names are case-sensitive and must exactly match the Airtable column names
- Open the Airtable base, check exact spelling, update the workflow's Insert node body

### 4. HubSpot contacts not being created (Workflow C)

**Cause:** Custom properties don't exist yet in HubSpot.
- HubSpot returns 400 with `PROPERTY_DOESNT_EXIST` if you try to set a property that hasn't been created
- Create all custom properties listed in the HubSpot Setup section above before activating Workflow C

### 5. n8n UI is unreachable after setup

**Cause:** SSL certificate not yet installed, or Nginx can't find the cert files.
- Before running certbot: access n8n directly on port 5678: `http://YOUR_IP:5678`
- After certbot: restart nginx: `docker restart lead_pipeline_nginx`
- Check nginx logs: `docker logs lead_pipeline_nginx`
- Verify cert files exist: `ls /etc/letsencrypt/live/YOUR_DOMAIN/`

---

## Daily Backup

Set up automated backups by adding to crontab:

```bash
# Run as root or the user who owns Docker
crontab -e

# Add this line (runs at 2am daily):
0 2 * * * /path/to/lead-pipeline/scripts/backup_n8n.sh >> /var/log/n8n_backup.log 2>&1
```

Backups are stored in `/var/backups/lead-pipeline/` and pruned after 14 days. Change the retention period by setting `RETENTION_DAYS=30` before running the script.

---

## Renewing SSL Certificates

Let's Encrypt certificates expire every 90 days. Add a renewal cron:

```bash
0 3 1 * * docker run --rm -v /etc/letsencrypt:/etc/letsencrypt -v /var/www/certbot:/var/www/certbot certbot/certbot renew --quiet && docker restart lead_pipeline_nginx
```

---

## Tearing Down and Rebuilding

The system is fully reproducible from `.env` + workflow JSON files:

```bash
# Tear down (preserves volumes)
docker compose down

# Tear down and delete all data
docker compose down -v

# Rebuild from scratch
bash scripts/setup.sh
# Then re-import workflows via n8n UI
```
