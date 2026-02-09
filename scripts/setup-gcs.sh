#!/bin/bash
set -euo pipefail

# GCS bucket setup for Polaris incident data storage
# This script is called by setup-environment.sh with required env vars set

# Validate required environment variables
if [ -z "${GCS_BUCKET:-}" ] || [ -z "${PROJECT_ID:-}" ] || [ -z "${REGION:-}" ]; then
    echo "Error: Required environment variables not set (GCS_BUCKET, PROJECT_ID, REGION)"
    echo "This script should be called by setup-environment.sh"
    exit 1
fi

echo "Setting up GCS bucket: gs://$GCS_BUCKET"

# Check if bucket already exists
if gsutil ls -p "$PROJECT_ID" "gs://$GCS_BUCKET" &> /dev/null; then
    echo "Bucket gs://$GCS_BUCKET already exists - skipping creation"
else
    echo "Creating bucket gs://$GCS_BUCKET in $REGION..."

    # Create bucket with recommended settings for production workloads
    # - Regional bucket for better performance and lower costs
    # - Uniform bucket-level access for consistent IAM
    # - Standard storage class by default
    gcloud storage buckets create "gs://$GCS_BUCKET" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --uniform-bucket-level-access \
        --public-access-prevention

    echo "Bucket created successfully"
fi

# Set lifecycle policy to move objects to nearline storage after 90 days
# This reduces storage costs for older incident data that's accessed less frequently
LIFECYCLE_CONFIG=$(cat <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "NEARLINE"
        },
        "condition": {
          "age": 90,
          "matchesStorageClass": ["STANDARD"]
        }
      }
    ]
  }
}
EOF
)

echo "Setting lifecycle policy (move to NEARLINE after 90 days)..."
echo "$LIFECYCLE_CONFIG" | gsutil lifecycle set /dev/stdin "gs://$GCS_BUCKET"

# Verify lifecycle policy was set
echo "Verifying lifecycle policy..."
gsutil lifecycle get "gs://$GCS_BUCKET" > /dev/null

echo "GCS bucket setup complete: gs://$GCS_BUCKET"
echo ""
echo "Bucket configuration:"
echo "  - Location: $REGION"
echo "  - Default storage class: STANDARD"
echo "  - Lifecycle: Move to NEARLINE after 90 days"
echo "  - Uniform bucket-level access: Enabled"
echo "  - Public access: Prevented"
