# Deployment runbook

Target: **Google Cloud Run** (container) + **Neon** (Postgres) + **GCS bucket**
for images. All in an EU region.

Set these once for the commands below:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="europe-west3"          # Frankfurt (near Neon eu-central-1)
export BUCKET="gs://sorginameiga-images"   # must be globally unique
gcloud config set project "$PROJECT_ID"
```

---

> **Status:** Project `sorgina-meiga` (nº 681872954393), billing on. Bucket
> `gs://sorginameiga-images` created in `europe-west3` and seeded (91 objects).

## 8c — Images bucket (GCS) ✅ DONE

The app reads and writes entity photos on the local filesystem under
`Public/images`. On Cloud Run that path is backed by a **GCS bucket mounted as a
volume**, so uploads persist and are shared across instances. No app code
changes — the mount is configured on the Cloud Run service (step 8e).

The bucket stays **private**: the app reads it through the mount and serves the
bytes itself; browsers never access GCS directly.

```bash
# 1. Enable the APIs (also needed later)
gcloud services enable run.googleapis.com \
    artifactregistry.googleapis.com \
    storage.googleapis.com \
    secretmanager.googleapis.com

# 2. Create the bucket (EU, uniform access, private)
gcloud storage buckets create "$BUCKET" \
    --location="$REGION" \
    --uniform-bucket-level-access

# 3. Seed the bucket with the current images (chrome + dog/gallery photos)
deploy/upload-images.sh "$BUCKET"
```

The Cloud Run service account gets read/write on the bucket in step 8e (so
admin photo uploads work).

---

## 8d — Build the image → Artifact Registry ✅ DONE (manual, via Cloud Build)

Repo: `europe-west3-docker.pkg.dev/sorgina-meiga/sorginameiga`. Built in the
cloud (native amd64) rather than cross-compiling on the ARM Mac:

```bash
gcloud artifacts repositories create sorginameiga \
    --repository-format=docker --location="$REGION"
```

**Two build paths** — pick by what changed. Both use `--machine-type=e2-highcpu-8`
(the build is a CPU-bound full `swift build -c release`; 8 vCPUs ≈ 7 min, the
default 1-vCPU machine ≈ 26 min — never omit the flag):

- **Fast path — source-only change** (no `Package.swift`/`Package.resolved` edits).
  Reuses the apt + `swift package resolve` layers from the Kaniko cache (~1-2 min
  saved; the compile still reruns because `COPY . .` sits above it):

  ```bash
  gcloud builds submit --region="$REGION" \
      --config=cloudbuild.yaml --project="$PROJECT_ID"
  ```

- **Clean path — dependency change** (you edited `Package.swift`/`Package.resolved`)
  **or when in doubt.** Skip the cache: once dependencies change, the cached
  dependency layer and everything below it is invalid, so the cache buys nothing
  and the extra cache pull is wasted time. Plain full build:

  ```bash
  gcloud builds submit --region="$REGION" \
      --tag="$REGION-docker.pkg.dev/$PROJECT_ID/sorginameiga/web:latest" \
      --timeout=2400s --machine-type=e2-highcpu-8
  ```

The cache is always *correct* either way (Kaniko invalidates changed layers
automatically — a stale-dependency image can't happen); the caveat is purely
about whether the cache saves time. See `cloudbuild.yaml` for details.

(A GitHub Actions pipeline can replace this later — see step 8g/optional.)

## 8e — Deploy to Cloud Run

The Neon connection string lives in Secret Manager as `database-url`. The images
bucket is mounted at `/app/Public/images`. Migrations were already applied to
Neon (8b), so the container only needs to `serve`.

```bash
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/sorginameiga/web:latest"
SA="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')-compute@developer.gserviceaccount.com"

# The Cloud Run service account needs to read the secret and read/write the bucket.
gcloud secrets add-iam-policy-binding database-url \
    --member="serviceAccount:$SA" --role="roles/secretmanager.secretAccessor"
gcloud storage buckets add-iam-policy-binding "$BUCKET" \
    --member="serviceAccount:$SA" --role="roles/storage.objectAdmin"

gcloud run deploy sorginameiga \
    --image="$IMAGE" \
    --region="$REGION" \
    --allow-unauthenticated \
    --port=8080 \
    --set-secrets=DATABASE_URL=database-url:latest \
    --add-volume=name=images,type=cloud-storage,bucket=sorginameiga-images \
    --add-volume-mount=volume=images,mount-path=/app/Public/images \
    --min-instances=0 --max-instances=4 \
    --cpu=1 --memory=512Mi --concurrency=80
```

Then open the service URL that `gcloud run deploy` prints and verify.

## 8f — Domain, DNS cutover & go-live
_(to be filled in — includes: re-extract the legacy seed fresh, map
sorginameiga.com, switch DNS off the DigitalOcean droplet, verify, rollback
window)_

## Backups

Basic, same-project backups (both in `europe-west3`).

**Photos** — the images bucket has **object versioning** on, with a lifecycle
rule that deletes noncurrent versions after 60 days and keeps at most 5 newer
versions per object (so reorders/overwrites don't grow unbounded):

```bash
gcloud storage buckets update gs://sorginameiga-images --versioning
gcloud storage buckets update gs://sorginameiga-images --lifecycle-file=deploy/images-lifecycle.json
```

**Database** — a daily `pg_dump` of Neon → `gs://sorginameiga-backups/db/`,
retained 90 days (bucket lifecycle). Runs as a Cloud Run Job built from
`deploy/backup/` (Cloud SDK image + `postgresql-client-18`; Neon runs Postgres
18, so the client must be ≥ 18), triggered by Cloud Scheduler at 03:00
Europe/Madrid.

```bash
# Build + create the job (DATABASE_URL from Secret Manager; SA needs objectAdmin on the backups bucket)
gcloud builds submit deploy/backup --region=europe-west3 \
    --tag=europe-west3-docker.pkg.dev/sorgina-meiga/sorginameiga/db-backup:latest
gcloud run jobs create db-backup --region=europe-west3 \
    --image=europe-west3-docker.pkg.dev/sorgina-meiga/sorginameiga/db-backup:latest \
    --set-secrets=DATABASE_URL=database-url:latest \
    --set-env-vars=BACKUP_BUCKET=gs://sorginameiga-backups \
    --max-retries=1 --task-timeout=600s

# Daily schedule (dedicated SA backup-scheduler@… with roles/run.invoker on the job)
gcloud scheduler jobs create http db-backup-daily --location=europe-west3 \
    --schedule="0 3 * * *" --time-zone="Europe/Madrid" --http-method=POST \
    --uri="https://run.googleapis.com/v2/projects/sorgina-meiga/locations/europe-west3/jobs/db-backup:run" \
    --oauth-service-account-email=backup-scheduler@sorgina-meiga.iam.gserviceaccount.com

# Run on demand:
gcloud run jobs execute db-backup --region=europe-west3 --wait
```

**Restore** a dump into a database:

```bash
gcloud storage cp gs://sorginameiga-backups/db/neon-YYYYMMDD-HHMMSS.sql.gz .
gunzip -c neon-YYYYMMDD-HHMMSS.sql.gz | psql "$TARGET_DATABASE_URL"
```
