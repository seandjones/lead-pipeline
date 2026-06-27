# Lead Generation Pipeline

Automated lead pipeline with two independent verticals running on the same n8n instance:

- **Service Businesses** — HVAC, plumbing, roofing, dental, legal, veterinary, etc. Identifies candidates for AI automation services based on website signals.
- **Real Estate Agents** — Targets agents in affluent markets who lack live chat and respond slowly to inquiries. Sends automated outreach if they don't reply within 15 minutes.

**Stack:** n8n · Apify · Airtable · Hunter.io · Apollo.io · Claude API · HubSpot · Twilio · SendGrid · Docker + Nginx

---

## Prerequisites

- A VPS with a public IP (Ubuntu 22.04 recommended, 2GB RAM minimum)
- A domain name pointed at that IP via an A record
- Docker Engine ≥ 24.x
- Docker Compose ≥ 2.x
- Accounts and API keys for: Apify, Airtable, Hunter.io, Apollo.io, Anthropic, HubSpot
- *(RE vertical only)* Twilio account (for SMS outreach) and SendGrid account (for email outreach)
- *(RE vertical only)* An email domain with inbound parse configured (SendGrid, Mailgun, or Postmark) for reply detection

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
3. Import the **service business** workflows in order:
   - `workflow_a_ingest.json`
   - `workflow_b_score.json`
   - `workflow_c_enrich_push.json`
   - `workflow_d_maintenance.json`
4. Import the **real estate** workflows (see the [Real Estate Agents Vertical](#real-estate-agents-vertical) section for full setup before activating):
   - `re_workflow_a_ingest.json`
   - `re_workflow_b_audit.json`
   - `re_workflow_c_response_timer.json`
   - `re_workflow_d_score.json`
   - `re_workflow_e_enrich_push.json`
   - `re_workflow_f_maintenance.json`

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

| Field Name | Field Type | Notes |
|---|---|---|
| `business_name` | Single line text | Primary field — rename default |
| `website` | URL | |
| `domain` | Single line text | |
| `phone` | Phone number | |
| `address` | Single line text | |
| `city` | Single line text | |
| `state` | Single line text | |
| `google_rating` | Number (precision: 1 decimal) | |
| `review_count` | Number (integer) | |
| `category` | **Single line text** | ⚠️ Must be Single line text — NOT Single select. Google Maps returns free-form category names (e.g., "Plumber", "Veterinarian", "Law firm") that change with each vertical. A Single select field will reject unknown values and block ingestion. |
| `has_website` | Checkbox | |
| `source` | Single select: Maps, Indeed, Craigslist | |
| `source_query` | Single line text | |
| `ai_score` | Number (integer) | |
| `ai_signals` | Long text | |
| `ai_summary` | Long text | |
| `website_fetch_status` | Single select: Pending, Success, Failed, No Website | |
| `contact_email` | Email | |
| `contact_name` | Single line text | |
| `mobile_phone` | Phone number | |
| `hubspot_contact_id` | Single line text | |
| `status` | Single select: Raw, Scored, Enriched, Pushed, Archived, Duplicate | |
| `date_added` | Date | |
| `date_scored` | Date | |
| `date_pushed` | Date | |
| `apify_run_id` | Single line text | |
| `notes` | Long text | |

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

## Managing Scrape Targets

Cities and verticals are configured in `.env` — no manual file editing required.

### Step 1 — Set your targets in `.env`

```dotenv
TARGET_CITIES='Denver CO,Aurora CO,Lakewood CO,Arvada CO,Westminster CO'
TARGET_VERTICALS='HVAC,plumbing,roofing'
```

- **`TARGET_CITIES`** — comma-separated list of `City STATE` strings (matches how you'd search Google Maps)
- **`TARGET_VERTICALS`** — comma-separated list of service types; any value works (dentist, landscaping, pest control, etc.)

The pipeline generates one Apify run per city × vertical combination. Five cities × three verticals = 15 runs.

### Step 2 — Generate input files

```bash
python3 scripts/generate_apify_inputs.py
```

This reads `TARGET_CITIES` and `TARGET_VERTICALS` from `.env`, clears any stale files in `scripts/apify_inputs/`, and writes one JSON per combination:

```
scripts/apify_inputs/
  denver_co_hvac.json
  denver_co_plumbing.json
  denver_co_roofing.json
  aurora_co_hvac.json
  ...
```

Each file contains five search strings for that city/vertical (e.g., `"HVAC in Denver CO"`, `"best HVAC in Denver CO"`) along with the proxy and crawl settings the Apify actor needs.

### Step 3 — Trigger the Apify runs

```bash
bash scripts/trigger_apify_runs.sh
```

This regenerates input files automatically (Steps 2 and 3 in one command), then fires each file against the Apify actor in sequence with a 5-second gap between runs. Run IDs and statuses are logged to `apify_runs.log`.

To trigger existing files without regenerating:

```bash
bash scripts/trigger_apify_runs.sh --skip-generate
```

To trigger a single file manually:

```bash
curl -X POST "https://api.apify.com/v2/acts/${APIFY_ACTOR_ID}/runs" \
  -H "Authorization: Bearer ${APIFY_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @scripts/apify_inputs/denver_co_hvac.json
```

### Step 4 — Verify data is flowing

1. In n8n: **Executions** → Workflow A should show a recent execution per Apify run
2. In Airtable: new records appear in the `Leads` table with `status = Raw`
3. Workflow B runs every 6 hours and scores `Raw` records that have `website_fetch_status = Pending`

### Adding new cities or verticals

1. Edit `TARGET_CITIES` or `TARGET_VERTICALS` in `.env`
2. Run `bash scripts/trigger_apify_runs.sh` — it regenerates and fires everything automatically

No other changes needed. The `category` field in Airtable receives whatever Google Maps returns (e.g., `Dentist`, `Law firm`) — ensure it is a **Single line text** field, not Single select, so it accepts any vertical without needing predefined options.

---

## Real Estate Agents Vertical

A second, fully independent pipeline targeting real estate agents in affluent markets. It runs on the same n8n instance and Docker stack but uses a **separate Airtable base**, a different webhook path, and two workflows that don't exist in the service-business pipeline: a **Vulnerability Audit** (live chat detection + contact form inquiry submission) and a **Response Timer** (outreach fires if the agent doesn't reply within 15 minutes).

**Why a separate base?** The data model is fundamentally different. Agents are the prospect; real estate listings (FSBO, Expired, Inbound) are a separate linked entity. Mixing this into the `Leads` table would corrupt filters, views, and reporting for both verticals.

### Workflow overview

| Workflow | File | Trigger | What it does |
|---|---|---|---|
| **A — Ingest** | `re_workflow_a_ingest.json` | Apify webhook (`re-apify-webhook`) | Ingests scraped agents → `Agents` table, deduplicates on phone + domain |
| **B — Vulnerability Audit** | `re_workflow_b_audit.json` | Cron every 6 hours | Fetches agent site, detects live chat, finds + submits contact form, records `inquiry_sent_at` |
| **C — Response Timer** | `re_workflow_c_response_timer.json` | Cron every 15 min + reply webhook | Fires SMS + email to agents who haven't replied within 15 min; separate webhook records replies |
| **D — AI Scoring** | `re_workflow_d_score.json` | Cron every 6 hours (offset +30 min) | Claude scores `Slow_Responder` agents; prompt tuned for RE CRM signals |
| **E — Enrichment & Push** | `re_workflow_e_enrich_push.json` | Cron every 4 hours | Hunter.io + Apollo enrichment → HubSpot deal (`{Agent} — Live Chat + Lead Response`) |
| **F — Maintenance** | `re_workflow_f_maintenance.json` | Cron Sunday 11:30pm | Archives agents stale 90+ days; weekly Slack report with slow-responder rate % |

### Status flow

```
Raw → Audited → Slow_Responder → Scored → Pushed
                 ↑                         ↑
        (Workflow C fires here)    (Workflow E closes loop)
```

Agents who reply within 15 minutes never reach `Slow_Responder` — they stay `Audited` and are eventually archived by Workflow F. Only slow responders (the core market) proceed to scoring and CRM.

---

### Step 1 — Create the RE Airtable base

1. Go to [airtable.com](https://airtable.com) → **Add a base** → **Start from scratch**
2. Name it `Real Estate Outreach`
3. Create two tables: **`Agents`** and **`RE_Leads`**
4. Copy the `appXXXX...` Base ID from the URL and set it as `AIRTABLE_BASE_ID_RE` in `.env`

#### `Agents` table fields

| Field Name | Field Type | Notes |
|---|---|---|
| `agent_name` | Single line text | Primary field |
| `agency_name` | Single line text | Brokerage or team name |
| `website` | URL | |
| `domain` | Single line text | Extracted hostname (no `www.`) |
| `phone` | Phone number | |
| `address` | Single line text | |
| `city` | Single line text | |
| `state` | Single line text | |
| `zip_code` | Single line text | |
| `google_rating` | Number (1 decimal) | |
| `review_count` | Number (integer) | |
| `source_query` | Single line text | Search string used in Apify |
| `apify_run_id` | Single line text | |
| `date_added` | Date | |
| `has_live_chat` | Checkbox | Set by Workflow B audit |
| `contact_form_found` | Checkbox | Set by Workflow B audit |
| `inquiry_sent_at` | Date and time | When the test inquiry was submitted |
| `responded_at` | Date and time | When they replied (set by reply webhook) |
| `response_time_minutes` | Number (integer) | Computed: `responded_at - inquiry_sent_at` |
| `outreach_triggered` | Checkbox | True after Workflow C fires outreach |
| `outreach_sent_at` | Date and time | When SMS/email was sent to agent |
| `ai_score` | Number (integer) | Claude score 1–10 |
| `ai_signals` | Long text | Comma-separated signals |
| `ai_summary` | Long text | One-sentence explanation |
| `contact_email` | Email | Hunter.io enrichment |
| `contact_name` | Single line text | Apollo enrichment (overwrites Hunter name) |
| `mobile_phone` | Phone number | Apollo enrichment |
| `hubspot_contact_id` | Single line text | After CRM push |
| `status` | Single select | Raw, Audited, Slow_Responder, Scored, Pushed, Archived |
| `date_scored` | Date | |
| `date_pushed` | Date | |
| `notes` | Long text | |
| `RE_Leads` | Link to another record | Links to the `RE_Leads` table |

#### `RE_Leads` table fields

Tracks actual real estate listings the agent is working — the hook for your pitch.

| Field Name | Field Type | Notes |
|---|---|---|
| `lead_address` | Single line text | Primary field — property address |
| `zip_code` | Single line text | |
| `lead_type` | Single select | FSBO, Expired, Inbound |
| `status` | Single select | New, Contacted, Under Contract, Closed, Dead |
| `list_date` | Date | When the listing hit MLS or Zillow |
| `days_on_market` | Number (integer) | |
| `asking_price` | Currency | |
| `source_url` | URL | Zillow / Realtor.com listing link |
| `assigned_agent` | Link to another record | Links back to `Agents` table |
| `date_added` | Date | |
| `notes` | Long text | |

> `RE_Leads` is populated manually (or via a future scrape of Zillow/Realtor FSBO/Expired data). It gives you context when reaching out — "I see you have a listing at 123 Main St that's been on market 45 days" is a much stronger opener than a cold message.

---

### Step 2 — Set RE targets in `.env`

```dotenv
# Real Estate Agents Vertical
AIRTABLE_BASE_ID_RE=appXXXXXXXXXXXXXX
AIRTABLE_TABLE_AGENTS=Agents
AIRTABLE_TABLE_RE_LEADS=RE_Leads

TARGET_CITIES_RE=Scottsdale AZ,Paradise Valley AZ,Arcadia AZ

INQUIRY_EMAIL_ALIAS=inquiry@yourdomain.com
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=your_auth_token
TWILIO_FROM_NUMBER=+12025551234
SENDGRID_API_KEY=SG.xxxxxxxxxx
```

**Choose affluent markets.** The vertical works best in cities where agents manage high-value listings — a 15-minute response-time gap on a $2M property is a compelling pain point.

---

### Step 3 — Generate and trigger RE scrape jobs

```bash
# Generate one input file per city in TARGET_CITIES_RE
python3 scripts/generate_re_apify_inputs.py

# Trigger all RE jobs (also regenerates inputs automatically)
bash scripts/trigger_re_apify_runs.sh

# Trigger without regenerating
bash scripts/trigger_re_apify_runs.sh --skip-generate
```

Input files are written to `scripts/re_apify_inputs/` (independent of `scripts/apify_inputs/` — the two directories are never mixed). Each file uses five search strings per city:

```
"top real estate agents Scottsdale AZ"
"best real estate agents Scottsdale AZ"
"real estate agent Scottsdale AZ"
"realtor Scottsdale AZ"
"real estate broker Scottsdale AZ"
```

---

### Step 4 — Configure the RE Apify webhook

In Apify Console, configure a webhook on the actor or individual runs:
- **Event:** `ACTOR.RUN.SUCCEEDED`
- **URL:** `https://YOUR_DOMAIN/webhook/re-apify-webhook`
- **Header:** `X-Webhook-Secret: YOUR_WEBHOOK_SECRET`

This routes to **RE Workflow A** (separate path from the service-biz webhook `apify-webhook`).

---

### Step 5 — Set up the reply webhook (Workflow C)

Workflow C includes a webhook endpoint at `https://YOUR_DOMAIN/webhook/re-reply-webhook`. Configure your email provider to POST inbound replies to this URL. When an agent replies to your inquiry email, the provider parses the reply and POSTs it here — Workflow C then matches the sender email to an `Agents` record and writes `responded_at` + `response_time_minutes`.

**SendGrid Inbound Parse setup:**
1. SendGrid → Settings → Inbound Parse → **Add Host & URL**
2. Receiving domain: the domain of `INQUIRY_EMAIL_ALIAS` (e.g., `yourdomain.com`)
3. Destination URL: `https://YOUR_DOMAIN/webhook/re-reply-webhook`
4. Check **POST the raw, full MIME message**

**Mailgun / Postmark:** both have equivalent "inbound routes" that POST the parsed email as JSON — point them at the same webhook URL.

> If you don't set this up, reply detection simply won't work — but everything else (audit, outreach trigger, scoring, CRM push) continues fine. You can manually set `responded_at` on any `Agents` record to capture a reply.

---

### Step 6 — HubSpot custom properties for RE

Before activating Workflow E, create these additional contact properties in HubSpot:

**HubSpot → Settings → Properties → Contact Properties → Create property**

| Label | Internal Name | Field Type |
|---|---|---|
| Response Time (minutes) | `response_time_minutes` | Number |
| Has Live Chat | `has_live_chat` | Single-line text |

The existing properties (`ai_automation_score`, `automation_pain_signals`, `lead_summary`, `google_rating`, `review_count`) are shared with the service-biz pipeline — no need to recreate them.

RE deals appear in HubSpot with the name format: **`{Agent Name} — Live Chat + Lead Response`**

---

### Step 7 — Import and activate RE workflows

In n8n UI → **Settings → Import Workflow** — import in this order:

1. `re_workflow_a_ingest.json`
2. `re_workflow_b_audit.json`
3. `re_workflow_c_response_timer.json`
4. `re_workflow_d_score.json`
5. `re_workflow_e_enrich_push.json`
6. `re_workflow_f_maintenance.json`

Activate them one at a time, starting with A, and verify data flows into Airtable before activating the next.

---

### How the Vulnerability Audit works (Workflow B)

For each `Raw` agent (up to 20 per run):

1. **Fetch website HTML** — 15-second timeout, follows redirects
2. **Detect live chat** — scans for JS signatures of 13 known chat widgets: Tawk.to, Drift, Intercom, LiveChat, Tidio, Crisp, Freshchat, Zendesk, Olark, LivePerson, SnapEngage, Smartsupp, Zopim
3. **Detect contact form** — looks for `<form>` elements with email/message fields
4. **Submit inquiry** — if a form is found, extracts field names and POSTs a realistic inquiry using the `INQUIRY_EMAIL_ALIAS` as the reply-to address
5. **Record `inquiry_sent_at`** — the timestamp that Workflow C uses to measure response time
6. **Update Airtable** → `status = Audited`

If the website can't be fetched, the agent is still marked `Audited` with `has_live_chat = false` and `contact_form_found = false`.

> **On contact form submission:** The audit submits a POST to the form's `action` URL using field names extracted from the page. Some forms use JavaScript-based submission (React, Vue) that this approach won't trigger — in those cases `inquiry_submitted` is false but the agent is still audited and the outreach message is sent via the phone number from Google Maps.

---

### How the Response Timer works (Workflow C)

Runs every 15 minutes. For each `Audited` agent where `inquiry_sent_at` is set and `outreach_triggered = false`:

- If **> 15 minutes have elapsed** since `inquiry_sent_at`:
  - Sends an SMS via Twilio to `mobile_phone` (falls back to `phone`)
  - Sends an email via SendGrid to `contact_email` (if enriched — runs after Workflow A, not E, so enrichment may not have run yet; email outreach fires later if the email is populated)
  - Sets `outreach_triggered = true`, `outreach_sent_at`, `status = Slow_Responder`
  - Sends a Slack alert

**The outreach message** (customizable in Workflow C's "Build Outreach Message" node):
> *"Hi [Name], I noticed your website doesn't have live chat — most home buyers decide on an agent within 15 minutes of reaching out. I help agents set this up in under 24 hours, so you never lose a lead to slow response time again. Worth a quick call?"*

Edit the `smsBody`, `emailSubject`, and `emailBody` variables in the **Build Outreach Message** Code node to fit your voice and offer.

---

### Monitoring the RE pipeline

Slack alerts from the RE workflows use the prefix `RE Workflow X` so they're easy to distinguish in a shared channel:

- `🔍 RE Audit: {agent_name}` — per-agent audit result with live chat + form status
- `⏱️ RE Outreach Triggered` — per-agent outreach sent, with elapsed time
- `📊 RE Workflow D — Agent Scored` — scoring batch complete
- `🏠 New RE Agent — Pushed to CRM` — per-agent CRM push with score + signals
- `📊 RE Weekly Pipeline Report` — includes slow-responder rate percentage

Airtable views to set up:
- `status = Raw` → unaudited, waiting for Workflow B
- `status = Audited` AND `has_live_chat = false` → vulnerability confirmed, waiting for response timer
- `status = Slow_Responder` → outreach sent, waiting for score
- `status = Scored` AND `ai_score >= 6` → ready for CRM push
- `status = Pushed` → closed loop

---

### RE pipeline troubleshooting

**Workflow B never detects the contact form / always shows `contact_form_found = false`**
- The site may use a JavaScript-rendered form (no `<form>` in the initial HTML)
- Verify manually: view source on the agent's website and search for `<form`
- Some Wordpress themes render forms via shortcodes that expand to `<form>` in HTML — these should be detected. React/Next.js single-page apps will not.

**Outreach fires but Twilio returns an error**
- Check that `TWILIO_FROM_NUMBER` is a valid Twilio number with SMS capability
- Check that the agent's phone number is a US mobile (Twilio can't text landlines)
- Twilio errors appear in the n8n Execution log for Workflow C

**Workflow C sends outreach to the same agent twice**
- `outreach_triggered` is set to `true` after the first send, which filters out the agent on subsequent runs
- If you see a double-send, check that the Airtable PATCH in "Update Agent — Slow Responder" succeeded — if it failed (network error), the agent stays `outreach_triggered = false` and can retrigger
- Add an n8n execution filter: check n8n execution logs for PATCH errors on that record

**`response_time_minutes` is never populated**
- The reply webhook (`re-reply-webhook`) is not configured or not receiving POSTs
- Verify your email provider is forwarding replies to `https://YOUR_DOMAIN/webhook/re-reply-webhook`
- Test with: `curl -X POST https://YOUR_DOMAIN/webhook/re-reply-webhook -H "Content-Type: application/json" -d '{"from":"agent@example.com"}'`
- The workflow matches by `contact_email` — if the agent replies from a different address than the enriched email, it won't match. Fallback: update `responded_at` manually in Airtable.

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

### 5. Airtable ingestion fails when adding a new vertical

**Cause:** The `category` field in the `Leads` table is set to **Single select** instead of **Single line text**.

Airtable's Single select field rejects values that aren't already in its predefined options list. When a new vertical (e.g., `dentist`, `pest control`) produces Google Maps results with a category name that doesn't exist in the list, Workflow A's `Insert to Airtable` node returns a 422 error and logs the failure to `Pipeline_Errors`.

**Fix:** In Airtable, open the `Leads` table → click the `category` column header → **Customize field** → change type to **Single line text**. No existing data is lost.

### 6. n8n UI is unreachable after setup

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
