#!/usr/bin/env bash
# Daily backup of n8n data volume and PostgreSQL database.
# Add to crontab: 0 2 * * * /path/to/lead-pipeline/scripts/backup_n8n.sh >> /var/log/n8n_backup.log 2>&1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/lead-pipeline}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS="${RETENTION_DAYS:-14}"

# Load .env
set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/.env"
set +a

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting backup..."

# ── PostgreSQL dump ────────────────────────────────────────────────────────────
PG_BACKUP_FILE="$BACKUP_DIR/postgres_${TIMESTAMP}.sql.gz"
echo "[$(date)] Dumping PostgreSQL to $PG_BACKUP_FILE"
docker exec lead_pipeline_postgres pg_dump \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  | gzip > "$PG_BACKUP_FILE"
echo "[$(date)] PostgreSQL backup complete: $(du -sh "$PG_BACKUP_FILE" | cut -f1)"

# ── n8n data volume ────────────────────────────────────────────────────────────
N8N_BACKUP_FILE="$BACKUP_DIR/n8n_data_${TIMESTAMP}.tar.gz"
echo "[$(date)] Backing up n8n data volume to $N8N_BACKUP_FILE"
docker run --rm \
  -v lead_pipeline_n8n_data:/source:ro \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf "/backup/n8n_data_${TIMESTAMP}.tar.gz" -C /source .
echo "[$(date)] n8n volume backup complete: $(du -sh "$N8N_BACKUP_FILE" | cut -f1)"

# ── Prune old backups ──────────────────────────────────────────────────────────
echo "[$(date)] Pruning backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +${RETENTION_DAYS} -delete
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete

echo "[$(date)] Backup complete. Files in $BACKUP_DIR:"
ls -lh "$BACKUP_DIR" | tail -10
