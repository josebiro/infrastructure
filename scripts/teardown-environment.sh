#!/bin/bash
set -euo pipefail

# Teardown script for Polaris infrastructure
# Usage: ./teardown-environment.sh [dev|prod]

# Validate arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 [dev|prod]"
    exit 1
fi

ENVIRONMENT=$1

if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    echo "Error: Environment must be 'dev' or 'prod'"
    exit 1
fi

# Set environment-specific variables
if [ "$ENVIRONMENT" == "prod" ]; then
    SUFFIX=""
    PROJECT_ID="polaris-prod"
    GCS_BUCKET="polaris-incidents"
else
    SUFFIX="-dev"
    PROJECT_ID="polaris-dev"
    GCS_BUCKET="polaris-incidents-dev"
fi

echo "=========================================="
echo "Polaris Infrastructure Teardown - $ENVIRONMENT"
echo "=========================================="
echo ""
echo "WARNING: This will DELETE the following resources:"
echo ""
echo "  GCS Bucket:"
echo "    - gs://$GCS_BUCKET (and all contents)"
echo ""
echo "  Service Accounts:"
echo "    - crawler${SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "    - pipeline${SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "    - polaris${SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
echo ""
echo "  Note: The following will NOT be deleted:"
echo "    - github-actions-deployer service account (shared across environments)"
echo "    - Artifact Registry repositories (contain tagged images)"
echo "    - Workload Identity Pool (shared across environments)"
echo ""
echo "Project: $PROJECT_ID"
echo ""

# Confirmation prompt
read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Teardown cancelled."
    exit 0
fi

echo ""
echo "Starting teardown process..."

# Set the active project
echo "Setting active project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID"

# 1. Delete GCS bucket
echo ""
echo "=========================================="
echo "Deleting GCS bucket..."
echo "=========================================="

if gsutil ls "gs://$GCS_BUCKET" &> /dev/null; then
    echo "Deleting bucket gs://$GCS_BUCKET and all contents..."
    gsutil -m rm -r "gs://$GCS_BUCKET" || true
    echo "Bucket deleted"
else
    echo "Bucket gs://$GCS_BUCKET does not exist - skipping"
fi

# 2. Delete application service accounts (but not deployer)
echo ""
echo "=========================================="
echo "Deleting service accounts..."
echo "=========================================="

SERVICE_ACCOUNTS=(
    "crawler${SUFFIX}"
    "pipeline${SUFFIX}"
    "polaris${SUFFIX}"
)

for sa_name in "${SERVICE_ACCOUNTS[@]}"; do
    sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"

    echo "Checking service account: $sa_name"

    if gcloud iam service-accounts describe "$sa_email" --project="$PROJECT_ID" &> /dev/null; then
        echo "  Deleting service account $sa_name..."

        # Remove IAM policy bindings first
        echo "  Removing IAM policy bindings..."
        gcloud iam service-accounts get-iam-policy "$sa_email" \
            --project="$PROJECT_ID" \
            --format=json | \
            jq -r '.bindings[]?.members[]? | select(startswith("principalSet://"))' | \
            while read -r member; do
                echo "    Removing binding for $member"
                gcloud iam service-accounts remove-iam-policy-binding "$sa_email" \
                    --member="$member" \
                    --role="roles/iam.workloadIdentityUser" \
                    --project="$PROJECT_ID" \
                    --quiet > /dev/null || true
            done

        # Delete the service account
        gcloud iam service-accounts delete "$sa_email" \
            --project="$PROJECT_ID" \
            --quiet

        echo "  Service account $sa_name deleted"
    else
        echo "  Service account $sa_name does not exist - skipping"
    fi
    echo ""
done

echo ""
echo "=========================================="
echo "Teardown complete!"
echo "=========================================="
echo ""
echo "Deleted resources:"
echo "  - GCS bucket: gs://$GCS_BUCKET"
echo "  - Service accounts: ${SERVICE_ACCOUNTS[*]}"
echo ""
echo "Preserved resources (manual cleanup required if needed):"
echo "  - github-actions-deployer service account"
echo "  - Artifact Registry repositories"
echo "  - Workload Identity Pool and provider"
echo ""
echo "To completely remove all infrastructure, you must manually:"
echo "  1. Delete Artifact Registry repositories:"
echo "     gcloud artifacts repositories delete incident-crawler --location=us --project=$PROJECT_ID"
echo "     gcloud artifacts repositories delete incident-pipeline --location=us --project=$PROJECT_ID"
echo "     gcloud artifacts repositories delete polaris --location=us --project=$PROJECT_ID"
echo ""
echo "  2. Delete Workload Identity (if no longer needed by any environment):"
echo "     gcloud iam workload-identity-pools delete github-actions --location=global --project=$PROJECT_ID"
echo ""
echo "  3. Delete github-actions-deployer service account (if no longer needed):"
echo "     gcloud iam service-accounts delete github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com --project=$PROJECT_ID"
echo ""
