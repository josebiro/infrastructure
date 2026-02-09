#!/bin/bash
set -euo pipefail

# Artifact Registry setup for Polaris container images
# This script is called by setup-environment.sh with required env vars set

# Validate required environment variables
if [ -z "${PROJECT_ID:-}" ]; then
    echo "Error: Required environment variable PROJECT_ID not set"
    echo "This script should be called by setup-environment.sh"
    exit 1
fi

# Configuration
LOCATION="us"  # Multi-region for better availability
REPOSITORIES=(
    "incident-crawler"
    "incident-pipeline"
    "polaris"
)

echo "Setting up Artifact Registry repositories in $PROJECT_ID..."
echo "Location: $LOCATION"
echo ""

# Function to create a repository if it doesn't exist
create_repository() {
    local repo_name=$1

    echo "Checking repository: $repo_name"

    # Check if repository exists
    if gcloud artifacts repositories describe "$repo_name" \
        --location="$LOCATION" \
        --project="$PROJECT_ID" &> /dev/null; then
        echo "  Repository $repo_name already exists - skipping"
    else
        echo "  Creating repository $repo_name..."

        # Create Docker repository with recommended settings
        # - Docker format for container images
        # - Immutable tags disabled (allows tag reuse for dev/latest tags)
        gcloud artifacts repositories create "$repo_name" \
            --repository-format=docker \
            --location="$LOCATION" \
            --project="$PROJECT_ID" \
            --description="Container images for ${repo_name} service"

        echo "  Repository $repo_name created successfully"
    fi

    # Output the repository URL for reference
    echo "  URL: ${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${repo_name}"
    echo ""
}

# Create all repositories
for repo in "${REPOSITORIES[@]}"; do
    create_repository "$repo"
done

echo "Artifact Registry setup complete"
echo ""
echo "Repository URLs:"
for repo in "${REPOSITORIES[@]}"; do
    echo "  ${repo}: ${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${repo}"
done
echo ""
echo "To configure Docker authentication, run:"
echo "  gcloud auth configure-docker ${LOCATION}-docker.pkg.dev"
echo ""
echo "To push images, use tags like:"
echo "  ${LOCATION}-docker.pkg.dev/${PROJECT_ID}/incident-crawler:latest"
