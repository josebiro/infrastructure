#!/bin/bash
set -euo pipefail

# Main orchestration script for Polaris infrastructure setup
# Usage: ./setup-environment.sh [dev|prod]

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

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Polaris Infrastructure Setup - $ENVIRONMENT"
echo "=========================================="

# Set environment-specific variables
# Note: Using shared project (incident-kb) with namespace separation for dev/prod
export PROJECT_ID="incident-kb"
export REGION="us-central1"

if [ "$ENVIRONMENT" == "prod" ]; then
    export SUFFIX=""
    export GCS_BUCKET="polaris-incidents"
else
    export SUFFIX="-dev"
    export GCS_BUCKET="polaris-incidents-dev"
fi

echo "Environment: $ENVIRONMENT"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "GCS Bucket: $GCS_BUCKET"
echo "Suffix: $SUFFIX"
echo ""

# Verify gcloud is installed and authenticated
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI is not installed"
    exit 1
fi

# Verify user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo "Error: No active gcloud authentication found. Please run 'gcloud auth login'"
    exit 1
fi

# Set the project
echo "Setting active project to $PROJECT_ID..."
if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
    echo "Error: Project $PROJECT_ID does not exist or you don't have access"
    exit 1
fi
gcloud config set project "$PROJECT_ID"

# Enable required GCP APIs
echo ""
echo "Enabling required GCP APIs..."
REQUIRED_APIS=(
    "container.googleapis.com"          # GKE
    "artifactregistry.googleapis.com"   # Container Registry
    "storage.googleapis.com"            # Cloud Storage
    "iam.googleapis.com"                # IAM
    "iamcredentials.googleapis.com"     # Workload Identity
    "cloudresourcemanager.googleapis.com" # Resource management
    "sts.googleapis.com"                # Security Token Service for WIF
    "aiplatform.googleapis.com"         # Vertex AI (embeddings, LLM)
)

for api in "${REQUIRED_APIS[@]}"; do
    echo "Enabling $api..."
    gcloud services enable "$api" --project="$PROJECT_ID"
done

echo ""
echo "API enablement complete."

# Run sub-scripts in order
echo ""
echo "=========================================="
echo "Step 1: Setting up GCS bucket..."
echo "=========================================="
bash "$SCRIPT_DIR/setup-gcs.sh"

echo ""
echo "=========================================="
echo "Step 2: Setting up Artifact Registry..."
echo "=========================================="
bash "$SCRIPT_DIR/setup-artifact-registry.sh"

echo ""
echo "=========================================="
echo "Step 3: Setting up Workload Identity..."
echo "=========================================="
bash "$SCRIPT_DIR/setup-workload-identity.sh"

echo ""
echo "=========================================="
echo "Infrastructure Setup Complete!"
echo "=========================================="
echo ""
echo "Environment: $ENVIRONMENT"
echo "Project: $PROJECT_ID"
echo "GCS Bucket: gs://$GCS_BUCKET"
echo "Artifact Registry: us-docker.pkg.dev/$PROJECT_ID"
echo ""
echo "Next steps:"
echo "1. Configure GitHub repository secrets with Workload Identity credentials"
echo "2. Deploy GKE cluster if needed"
echo "3. Set up CI/CD pipelines in .github/workflows/"
echo ""
