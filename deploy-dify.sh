#!/bin/bash

# Dify GCP Deployment Script
# This script automates the complete deployment process for Dify on Google Cloud Platform

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}[STEP $1]${NC} $2"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_step "0" "Checking prerequisites..."

    if ! command_exists gcloud; then
        print_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    if ! command_exists terraform; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi

    if ! command_exists gsutil; then
        print_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Main script
main() {
    # Check arguments
    if [ $# -ne 2 ]; then
        echo "Usage: $0 <PROJECT_ID> <REGION>"
        echo "Example: $0 my-project asia-northeast1"
        exit 1
    fi

    PROJECT_ID="$1"
    REGION="$2"

    echo "Starting Dify deployment with:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo ""

    check_prerequisites

    # Change to script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR"

    # Step 1: Enable required APIs
    print_step "1" "Enabling required Google Cloud APIs..."
    gcloud services enable \
        artifactregistry.googleapis.com \
        compute.googleapis.com \
        servicenetworking.googleapis.com \
        redis.googleapis.com \
        vpcaccess.googleapis.com \
        run.googleapis.com \
        storage.googleapis.com \
        sqladmin.googleapis.com \
        file.googleapis.com \
        cloudbuild.googleapis.com \
        containerregistry.googleapis.com \
        --project="$PROJECT_ID" \
        --quiet
    print_success "APIs enabled successfully"

    # Step 2: Create Terraform state bucket
    print_step "2" "Creating Terraform state bucket..."
    BUCKET_NAME="${PROJECT_ID}-terraform-state-dify"

    if ! gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME" 2>/dev/null; then
        gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"
        print_success "Created bucket: gs://$BUCKET_NAME"
    else
        print_warning "Bucket already exists: gs://$BUCKET_NAME"
    fi

    # Update provider.tf
    sed -i.bak "s/your-tfstate-bucket/$BUCKET_NAME/g" terraform/environments/dev/provider.tf
    print_success "Updated provider.tf with bucket name"

    # Step 3: Initialize Terraform
    print_step "3" "Initializing Terraform..."
    cd terraform/environments/dev
    terraform init -upgrade
    print_success "Terraform initialized"

    # Step 4: Update terraform.tfvars
    print_step "4" "Updating terraform.tfvars..."
    sed -i.bak "s/your-project-id/$PROJECT_ID/g" terraform.tfvars
    sed -i.bak "s/your-region/$REGION/g" terraform.tfvars
    sed -i.bak "s/asia-northeast1/$REGION/g" terraform.tfvars

    # Generate and replace secret keys if they are still default values
    if grep -q 'secret_key.*=.*"your-secret-key"' terraform.tfvars; then
        SECRET_KEY=$(openssl rand -base64 42)
        sed -i.bak "s/your-secret-key/$SECRET_KEY/g" terraform.tfvars
        print_success "Generated and replaced secret_key"
    fi

    if grep -q 'plugin_daemon_key.*=.*"your-plugin-daemon-key"' terraform.tfvars; then
        PLUGIN_DAEMON_KEY=$(openssl rand -base64 42)
        sed -i.bak "s/your-plugin-daemon-key/$PLUGIN_DAEMON_KEY/g" terraform.tfvars
        print_success "Generated and replaced plugin_daemon_key"
    fi

    if grep -q 'plugin_dify_inner_api_key.*=.*"your-plugin-dify-inner-api-key"' terraform.tfvars; then
        PLUGIN_INNER_API_KEY=$(openssl rand -base64 42)
        sed -i.bak "s/your-plugin-dify-inner-api-key/$PLUGIN_INNER_API_KEY/g" terraform.tfvars
        print_success "Generated and replaced plugin_dify_inner_api_key"
    fi

    print_success "Updated terraform.tfvars"

    # Step 5: Create Artifact Registry repositories
    print_step "5" "Creating Artifact Registry repositories..."
    terraform apply -target=module.registry -auto-approve
    print_success "Artifact Registry repositories created"

    # Step 6: Build and push container images
    print_step "6" "Building and pushing container images..."
    cd ../../..
    chmod +x docker/cloudbuild.sh
    ./docker/cloudbuild.sh "$PROJECT_ID" "$REGION"
    print_success "Container images built and pushed"

    # Step 7: Apply Terraform configuration
    print_step "7" "Applying Terraform configuration..."
    cd terraform/environments/dev
    terraform apply -auto-approve
    print_success "Terraform apply completed"

    # Step 8: Display Dify URL
    print_step "8" "Getting Dify service URL..."
    sleep 10  # Wait for services to be ready

    DIFY_URL=$(gcloud run services describe dify-service \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format="value(status.url)" 2>/dev/null || echo "")

    if [ -n "$DIFY_URL" ]; then
        echo ""
        echo "=========================================="
        echo "🎉 Dify deployment completed successfully!"
        echo "=========================================="
        echo ""
        echo "Dify Web Application URL:"
        echo "$DIFY_URL"
        echo ""
        echo "You can now:"
        echo "1. Open the URL in your browser"
        echo "2. Create your first account"
        echo "3. Start using Dify!"
        echo ""
        echo "To clean up resources later, run:"
        echo "./cleanup-resources.sh $PROJECT_ID"
    else
        print_warning "Could not retrieve Dify URL. Services might still be starting up."
        echo "You can check the URL later with:"
        echo "gcloud run services list --project=$PROJECT_ID --region=$REGION --format='table(metadata.name,status.url)'"
    fi
}

# Run main function
main "$@"