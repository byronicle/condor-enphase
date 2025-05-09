#!/bin/sh
set -euo pipefail

ORG="enphase"
BUCKET_NAME="solar"
TOKEN_PATH="/token/influxdb_write.token"

# ------------------------------------------------------------------
# 1) Obtain bucket ID in JSON → grep out "id"
# ------------------------------------------------------------------
BUCKET_ID=$(influx bucket list \
  --org   "$ORG" \
  --name  "$BUCKET_NAME" \
  --hide-headers \
  | cut -f 1)

# Sanity‑check
[ -n "$BUCKET_ID" ] || { echo "Bucket $BUCKET_NAME not found"; exit 1; }

# ------------------------------------------------------------------
# 2) Create read+write token for that bucket ID
# ------------------------------------------------------------------
WRITE_TOKEN=$(influx auth create \
  --org  "$ORG" \
  --read-bucket  "$BUCKET_ID" \
  --write-bucket "$BUCKET_ID" \
  --description "solar-readwrite" \
  --hide-headers | cut -f 3)

echo "$WRITE_TOKEN" | tee "$TOKEN_PATH"
echo "Writer token created for bucket $BUCKET_NAME (ID: $BUCKET_ID)"
