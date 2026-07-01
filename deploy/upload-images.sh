#!/usr/bin/env bash
#
# Uploads all site images to the GCS bucket that Cloud Run mounts at
# /app/Public/images. Run once to seed the bucket, and again whenever the baked
# images change. The bucket stays PRIVATE — Cloud Run reads it through the
# mounted volume and the app serves the bytes; browsers never hit GCS directly.
#
# Usage: deploy/upload-images.sh gs://BUCKET_NAME
#
set -euo pipefail

BUCKET="${1:?Usage: deploy/upload-images.sh gs://BUCKET_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Uploading $SCRIPT_DIR/Public/images -> $BUCKET"
gcloud storage rsync --recursive "$SCRIPT_DIR/Public/images" "$BUCKET"
echo "Done."
