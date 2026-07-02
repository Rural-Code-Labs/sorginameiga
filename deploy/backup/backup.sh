#!/usr/bin/env bash
# Dumps the production Postgres database (Neon) and uploads a gzipped SQL dump
# to the backups bucket. Run as a scheduled Cloud Run Job.
#
# Env:
#   DATABASE_URL   Neon connection string (from Secret Manager `database-url`)
#   BACKUP_BUCKET  destination bucket, e.g. gs://sorginameiga-backups
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${BACKUP_BUCKET:?BACKUP_BUCKET is required}"

timestamp="$(date -u +%Y%m%d-%H%M%S)"
file="neon-${timestamp}.sql.gz"

echo "Dumping database → ${file}"
pg_dump "$DATABASE_URL" | gzip -9 > "/tmp/${file}"

echo "Uploading → ${BACKUP_BUCKET}/db/${file}"
gcloud storage cp "/tmp/${file}" "${BACKUP_BUCKET}/db/${file}"

echo "Backup complete: ${BACKUP_BUCKET}/db/${file} ($(du -h "/tmp/${file}" | cut -f1))"
