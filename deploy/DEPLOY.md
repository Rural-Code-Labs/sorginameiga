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

## 8c — Images bucket (GCS)

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

## 8d — CI build → Artifact Registry
_(to be filled in)_

## 8e — Deploy to Cloud Run
_(to be filled in — includes: secrets DATABASE_URL & ADMIN_PASSWORD, the GCS
volume mount at /app/Public/images, region, min/max instances)_

## 8f — Domain, DNS cutover & go-live
_(to be filled in — includes: re-extract the legacy seed fresh, map
sorginameiga.com, switch DNS off the DigitalOcean droplet, verify, rollback
window)_
