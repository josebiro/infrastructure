#!/bin/bash
set -euo pipefail

# Workload Identity Federation setup for GitHub Actions and GKE service accounts
# This script is called by setup-environment.sh with required env vars set

# Validate required environment variables
if [ -z "${PROJECT_ID:-}" ] || [ -z "${SUFFIX:-}" ] || [ -z "${GCS_BUCKET:-}" ]; then
    echo "Error: Required environment variables not set (PROJECT_ID, SUFFIX, GCS_BUCKET)"
    echo "This script should be called by setup-environment.sh"
    exit 1
fi

# Configuration
POOL_ID="github-actions"
PROVIDER_ID="github-oidc"
GITHUB_ORG="josebiro"  # Update this to match your GitHub organization/user

# GitHub repository names for attribute mapping
REPOS=(
    "polaris"
    "incident_crawler"
    "incident_pipeline"
)

echo "Setting up Workload Identity Federation for GitHub Actions..."
echo "Project: $PROJECT_ID"
echo "GitHub Org: $GITHUB_ORG"
echo ""

# 1. Create service accounts for each service
echo "=========================================="
echo "Creating service accounts..."
echo "=========================================="

SERVICE_ACCOUNTS=(
    "github-actions-deployer:Service account for GitHub Actions CI/CD deployments"
    "crawler${SUFFIX}:Service account for incident-crawler application"
    "pipeline${SUFFIX}:Service account for incident-pipeline application"
    "polaris${SUFFIX}:Service account for polaris application"
)

for sa_info in "${SERVICE_ACCOUNTS[@]}"; do
    IFS=':' read -r sa_name sa_description <<< "$sa_info"
    sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"

    echo "Checking service account: $sa_name"

    if gcloud iam service-accounts describe "$sa_email" --project="$PROJECT_ID" &> /dev/null; then
        echo "  Service account $sa_name already exists - skipping"
    else
        echo "  Creating service account $sa_name..."
        gcloud iam service-accounts create "$sa_name" \
            --display-name="$sa_name" \
            --description="$sa_description" \
            --project="$PROJECT_ID"
        echo "  Created: $sa_email"
    fi
    echo ""
done

# 2. Create Workload Identity Pool for GitHub Actions
echo "=========================================="
echo "Setting up Workload Identity Pool..."
echo "=========================================="

if gcloud iam workload-identity-pools describe "$POOL_ID" \
    --location="global" \
    --project="$PROJECT_ID" &> /dev/null; then
    echo "Workload Identity Pool $POOL_ID already exists - skipping"
else
    echo "Creating Workload Identity Pool: $POOL_ID"
    gcloud iam workload-identity-pools create "$POOL_ID" \
        --location="global" \
        --display-name="GitHub Actions Pool" \
        --description="Workload Identity Pool for GitHub Actions OIDC authentication" \
        --project="$PROJECT_ID"
    echo "Pool created successfully"
fi

# 3. Create OIDC provider for GitHub
echo ""
echo "=========================================="
echo "Setting up OIDC provider..."
echo "=========================================="

if gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
    --workload-identity-pool="$POOL_ID" \
    --location="global" \
    --project="$PROJECT_ID" &> /dev/null; then
    echo "OIDC provider $PROVIDER_ID already exists - skipping"
else
    echo "Creating OIDC provider: $PROVIDER_ID"
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
        --workload-identity-pool="$POOL_ID" \
        --location="global" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
        --attribute-condition="assertion.repository_owner == '$GITHUB_ORG'" \
        --project="$PROJECT_ID"
    echo "Provider created successfully"
fi

# 4. Grant IAM permissions to GitHub Actions deployer service account
echo ""
echo "=========================================="
echo "Configuring IAM permissions..."
echo "=========================================="

DEPLOYER_SA="github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com"

# Roles needed for GitHub Actions to deploy to GKE and push to Artifact Registry
DEPLOYER_ROLES=(
    "roles/container.developer"          # Deploy to GKE
    "roles/artifactregistry.writer"      # Push container images
    "roles/iam.serviceAccountUser"       # Use service accounts
    "roles/storage.objectAdmin"          # Manage GCS objects for state/backups
)

echo "Granting roles to $DEPLOYER_SA..."
for role in "${DEPLOYER_ROLES[@]}"; do
    echo "  Granting $role..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$DEPLOYER_SA" \
        --role="$role" \
        --condition=None \
        --quiet > /dev/null
done

# 5. Allow GitHub Actions to impersonate the deployer service account
echo ""
echo "Configuring Workload Identity Federation bindings..."

# Get project number (required for principalSet format)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

for repo in "${REPOS[@]}"; do
    # Use correct principalSet format with project number
    PRINCIPAL="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_ORG}/${repo}"

    echo "  Binding ${GITHUB_ORG}/${repo} to $DEPLOYER_SA..."

    gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER_SA" \
        --member="$PRINCIPAL" \
        --role="roles/iam.workloadIdentityUser" \
        --project="$PROJECT_ID" \
        --quiet > /dev/null
done

# 6. Grant GCS permissions to application service accounts
echo ""
echo "Granting GCS permissions to application service accounts..."

APP_SERVICE_ACCOUNTS=(
    "crawler${SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
    "pipeline${SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
)

for sa in "${APP_SERVICE_ACCOUNTS[@]}"; do
    echo "  Granting storage.objectAdmin to $sa for gs://$GCS_BUCKET..."

    # Grant bucket-level permissions
    gsutil iam ch "serviceAccount:${sa}:objectAdmin" "gs://$GCS_BUCKET"
done

# Polaris service account gets read-only access
POLARIS_SA="polaris${SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "  Granting storage.objectViewer to $POLARIS_SA for gs://$GCS_BUCKET..."
gsutil iam ch "serviceAccount:${POLARIS_SA}:objectViewer" "gs://$GCS_BUCKET"

# 7. Grant Vertex AI permissions to polaris service account (embeddings + LLM)
echo ""
echo "Granting Vertex AI permissions to polaris service account..."
echo "  Granting roles/aiplatform.user to $POLARIS_SA..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$POLARIS_SA" \
    --role="roles/aiplatform.user" \
    --condition=None \
    --quiet > /dev/null

echo ""
echo "=========================================="
echo "Workload Identity setup complete!"
echo "=========================================="
echo ""
echo "Service Accounts created:"
echo "  - github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
echo "  - crawler${SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "  - pipeline${SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "  - polaris${SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
echo ""
echo "Workload Identity Pool (use project number format for providers):"
echo "  projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
echo ""
echo "GitHub Actions Configuration:"
echo "Add these to your repository variables (Settings > Secrets and variables > Actions > Variables):"
echo ""
echo "  GCP_PROJECT_ID: $PROJECT_ID"
echo "  GCP_WORKLOAD_IDENTITY_PROVIDER: projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
echo "  GCP_SERVICE_ACCOUNT: $DEPLOYER_SA"
echo ""
echo "Use in GitHub Actions workflow:"
echo ""
cat <<'EOF'
  - name: Authenticate to Google Cloud
    uses: google-github-actions/auth@v2
    with:
      workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}
EOF
echo ""
