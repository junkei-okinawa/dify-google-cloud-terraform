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

# Check prerequisites and authentication
check_prerequisites() {
    print_step "0" "Checking prerequisites and authentication..." 

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

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        print_error "You are not logged in to gcloud. Please run 'gcloud auth login' and 'gcloud auth application-default login'."
        exit 1
    fi

    # Check gcloud application-default authentication
    if [ ! -f "${HOME}/.config/gcloud/application_default_credentials.json" ]; then
        print_warning "Application default credentials not found. Please run 'gcloud auth application-default login'."
        exit 1
    fi

    print_success "Prerequisites and authentication check passed"
}

# Main script
main() {
    # Check arguments
    PLAN_ONLY=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --plan-only)
                PLAN_ONLY=true
                shift
                ;;
            *)
                break
                ;;
esac
    done

    if [ $# -ne 2 ]; then
        echo "Usage: $0 [--plan-only] <PROJECT_ID> <REGION>"
        echo "Example: $0 --plan-only my-project asia-northeast1"
        exit 1
    fi

    PROJECT_ID="$1"
    REGION="$2"

    echo "Starting Dify deployment with:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    if [ "$PLAN_ONLY" = true ]; then
        echo "  Mode: Plan-only"
    fi
    echo ""

    check_prerequisites

    # Set gcloud project to ensure all commands use the correct project
    print_step "0.1" "Setting gcloud project to $PROJECT_ID..."
    gcloud config set project "$PROJECT_ID"
    print_success "gcloud project set to $PROJECT_ID"

    # Change to script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR"

    if [ "$PLAN_ONLY" = true ]; then
        # Skip Step 1: Enable required APIs
        # Skip Step 2: Create Terraform state bucket
        echo "Skipping Steps 1 and 2 as not in plan-only mode"
    else
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

        # Grant Cloud Build service account permissions for Artifact Registry
        print_step "1.1" "Setting up Cloud Build service account permissions..."
        PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
        CLOUDBUILD_SA="$PROJECT_NUMBER@cloudbuild.gserviceaccount.com"
        
        # Grant Artifact Registry Writer role to Cloud Build service account
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$CLOUDBUILD_SA" \
            --role="roles/artifactregistry.writer" \
            --quiet
        print_success "Granted Artifact Registry permissions to Cloud Build service account"

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
    fi

    # Step 3: Initialize Terraform
    print_step "3" "Initializing Terraform..."
    cd terraform/environments/dev
    terraform init -upgrade
    print_success "Terraform initialized"

    # Step 3.1: Import existing resources to Terraform state
    print_step "3.1" "Importing existing resources to Terraform state..."
    IMPORTED_RESOURCES=()
    
    # Import service accounts
    if gcloud iam service-accounts describe "dify-service-account@$PROJECT_ID.iam.gserviceaccount.com" --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.cloudrun.google_service_account.dify_service_account 2>/dev/null || true
        if terraform import module.cloudrun.google_service_account.dify_service_account "projects/$PROJECT_ID/serviceAccounts/dify-service-account@$PROJECT_ID.iam.gserviceaccount.com" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify-service-account")
            print_success "Imported dify-service-account"
        else
            print_warning "dify-service-account import failed"
        fi
    fi
    
    if gcloud iam service-accounts describe "storage-admin-for-dify@$PROJECT_ID.iam.gserviceaccount.com" --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.storage.google_service_account.storage_admin 2>/dev/null || true
        if terraform import module.storage.google_service_account.storage_admin "projects/$PROJECT_ID/serviceAccounts/storage-admin-for-dify@$PROJECT_ID.iam.gserviceaccount.com" 2>/dev/null; then
            IMPORTED_RESOURCES+=("storage-admin-for-dify")
            print_success "Imported storage-admin-for-dify"
        else
            print_warning "storage-admin-for-dify import failed"
        fi
    fi
    
    # Import storage bucket
    BUCKET_NAME="${PROJECT_ID}_dify"
    if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
        terraform state rm module.storage.google_storage_bucket.dify_storage 2>/dev/null || true
        if terraform import module.storage.google_storage_bucket.dify_storage "$BUCKET_NAME" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify_storage")
            print_success "Imported dify_storage bucket"
        else
            print_warning "dify_storage bucket import failed"
        fi
    fi
    
    # Import Redis instance
    if gcloud redis instances describe dify-redis --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.redis.google_redis_instance.dify_redis 2>/dev/null || true
        if terraform import module.redis.google_redis_instance.dify_redis "projects/$PROJECT_ID/locations/$REGION/instances/dify-redis" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify-redis")
            print_success "Imported dify-redis"
        else
            print_warning "dify-redis import failed"
        fi
    fi
    
    # Import Filestore instance
    FILESTORE_LOCATION="${REGION}-b"
    if gcloud filestore instances describe dify-filestore --location="$FILESTORE_LOCATION" --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.filestore.google_filestore_instance.default 2>/dev/null || true
        if terraform import module.filestore.google_filestore_instance.default "projects/$PROJECT_ID/locations/$FILESTORE_LOCATION/instances/dify-filestore" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify-filestore")
            print_success "Imported dify-filestore"
        else
            print_warning "dify-filestore import failed"
        fi
    fi
    
    # Import VPC network
    if gcloud compute networks describe dify-vpc --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.network.google_compute_network.dify_vpc 2>/dev/null || true
        if terraform import module.network.google_compute_network.dify_vpc "projects/$PROJECT_ID/global/networks/dify-vpc" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify-vpc")
            print_success "Imported dify-vpc"
        else
            print_warning "dify-vpc import failed"
        fi
    fi
    
    # Import VPC subnet
    if gcloud compute networks subnets describe dify-subnet --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.network.google_compute_subnetwork.dify_subnet 2>/dev/null || true
        if terraform import module.network.google_compute_subnetwork.dify_subnet "projects/$PROJECT_ID/regions/$REGION/subnetworks/dify-subnet" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify-subnet")
            print_success "Imported dify-subnet"
        else
            print_warning "dify-subnet import failed"
        fi
    fi
    
    # Import Artifact Registry repositories
    if gcloud artifacts repositories describe dify-nginx-repo --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.registry.google_artifact_registry_repository.nginx_repo 2>/dev/null || true
        if terraform import module.registry.google_artifact_registry_repository.nginx_repo "projects/$PROJECT_ID/locations/$REGION/repositories/dify-nginx-repo" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify-nginx-repo")
            print_success "Imported dify-nginx-repo"
        else
            print_warning "dify-nginx-repo import failed"
        fi
    fi
    
    if gcloud artifacts repositories describe dify-api-repo --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.registry.google_artifact_registry_repository.api_repo 2>/dev/null || true
        if terraform import module.registry.google_artifact_registry_repository.api_repo "projects/$PROJECT_ID/locations/$REGION/repositories/dify-api-repo" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify-api-repo")
            print_success "Imported dify-api-repo"
        else
            print_warning "dify-api-repo import failed"
        fi
    fi
    
    if gcloud artifacts repositories describe dify-web-repo --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.registry.google_artifact_registry_repository.web_repo 2>/dev/null || true
        if terraform import module.registry.google_artifact_registry_repository.web_repo "projects/$PROJECT_ID/locations/$REGION/repositories/dify-web-repo" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify-web-repo")
            print_success "Imported dify-web-repo"
        else
            print_warning "dify-web-repo import failed"
        fi
    fi
    
    if gcloud artifacts repositories describe dify-plugin-daemon-repo --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.registry.google_artifact_registry_repository.plugin_daemon_repo 2>/dev/null || true
        if terraform import module.registry.google_artifact_registry_repository.plugin_daemon_repo "projects/$PROJECT_ID/locations/$REGION/repositories/dify-plugin-daemon-repo" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify-plugin-daemon-repo")
            print_success "Imported dify-plugin-daemon-repo"
        else
            print_warning "dify-plugin-daemon-repo import failed"
        fi
    fi
    
    if gcloud artifacts repositories describe dify-sandbox-repo --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        terraform state rm module.registry.google_artifact_registry_repository.sandbox_repo 2>/dev/null || true
        if terraform import module.registry.google_artifact_registry_repository.sandbox_repo "projects/$PROJECT_ID/locations/$REGION/repositories/dify-sandbox-repo" 2>/dev/null; then
            IMPORTED_RESOURCES+=("dify-sandbox-repo")
            print_success "Imported dify-sandbox-repo"
        else
            print_warning "dify-sandbox-repo import failed"
        fi
    fi

    # Step 4: Update terraform.tfvars
    print_step "4" "Updating terraform.tfvars..."
    sed -i.bak "s/your-project-id/$PROJECT_ID/g" terraform.tfvars
    sed -i.bak "s/your-region/$REGION/g" terraform.tfvars

    # Generate and replace secret keys if they are still default values
    if grep -q 'secret_key.*=.*"your-secret-key"' terraform.tfvars; then
        SECRET_KEY=$(openssl rand -base64 42)
        sed -i.bak "s|your-secret-key|$SECRET_KEY|g" terraform.tfvars
        print_success "Generated and replaced secret_key"
    fi

    if grep -q 'plugin_daemon_key.*=.*"your-plugin-daemon-key"' terraform.tfvars; then
        PLUGIN_DAEMON_KEY=$(openssl rand -base64 42)
        sed -i.bak "s|your-plugin-daemon-key|$PLUGIN_DAEMON_KEY|g" terraform.tfvars
        print_success "Generated and replaced plugin_daemon_key"
    fi

    if grep -q 'plugin_dify_inner_api_key.*=.*"your-plugin-dify-inner-api-key"' terraform.tfvars; then
        PLUGIN_INNER_API_KEY=$(openssl rand -base64 42)
        sed -i.bak "s|your-plugin-dify-inner-api-key|$PLUGIN_INNER_API_KEY|g" terraform.tfvars
        print_success "Generated and replaced plugin_dify_inner_api_key"
    fi

    print_success "Updated terraform.tfvars"

    if [ "$PLAN_ONLY" = true ]; then
        print_step "5" "Planning Terraform configuration (plan-only mode)..."
        terraform plan -var-file="terraform.tfvars"
        print_success "Terraform plan completed"
        exit 0
    fi

    # Step 5: Check Artifact Registry repositories
    print_step "5" "Checking Artifact Registry repositories..."
    # All repositories should be imported in Step 3.1, so just verify they exist
    EXISTING_REPOS=$(gcloud artifacts repositories list --project="$PROJECT_ID" --location="$REGION" --filter="name~dify*" --format="value(name)" | wc -l)
    if [ "$EXISTING_REPOS" -eq 5 ]; then
        print_success "All Artifact Registry repositories exist and are imported"
    else
        print_warning "Some repositories are missing. Expected 5, found $EXISTING_REPOS. Creating missing repositories with Terraform."
        # Apply only the registry module to create missing repositories
        terraform apply -target=module.registry -auto-approve
        print_success "Missing repositories created."
    fi

    # Step 6: Build and push container images
    print_step "6" "Building and pushing container images..."
    cd ../../..
    # Check if required images exist (only nginx and api need to be built locally)
    NGINX_IMAGE_EXISTS=$(gcloud artifacts docker images list "${REGION}-docker.pkg.dev/$PROJECT_ID/dify-nginx-repo" --format="value(uri)" | grep -q "dify-nginx:latest" && echo "true" || echo "false")
    API_IMAGE_EXISTS=$(gcloud artifacts docker images list "${REGION}-docker.pkg.dev/$PROJECT_ID/dify-api-repo" --format="value(uri)" | grep -q "dify-api:latest" && echo "true" || echo "false")
    
    if [ "$NGINX_IMAGE_EXISTS" = "false" ] || [ "$API_IMAGE_EXISTS" = "false" ]; then
        print_warning "Some container images not found. Building from scratch..."
        chmod +x docker/cloudbuild.sh
        ./docker/cloudbuild.sh "$PROJECT_ID" "$REGION"
        print_success "Container images built and pushed"
    else
        print_warning "All required container images already exist in Artifact Registry. Skipping build and push."
        echo "If you want to rebuild images, delete them first:"
        echo "gcloud artifacts docker images delete \$(gcloud artifacts docker images list ${REGION}-docker.pkg.dev/$PROJECT_ID/dify-nginx-repo --format='value(uri)') --delete-tags"
        echo "gcloud artifacts docker images delete \$(gcloud artifacts docker images list ${REGION}-docker.pkg.dev/$PROJECT_ID/dify-api-repo --format='value(uri)') --delete-tags"
    fi

    # Step 7: Apply Terraform configuration
    print_step "7" "Applying Terraform configuration..."
    cd terraform/environments/dev
    
    # Check what changes terraform plans to make
    print_step "7.1" "Checking terraform plan..."
    if terraform plan -var-file="terraform.tfvars" | grep -E "(Plan:|No changes)"; then
        print_success "Terraform plan shows no unexpected changes"
    else
        print_warning "Terraform plan shows changes. Please review the plan above."
        echo "Do you want to continue? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_error "Deployment cancelled by user"
            exit 1
        fi
    fi
    
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
        echo "./cleanup-resources.sh $PROJECT_ID $REGION"
    else
        print_warning "Could not retrieve Dify URL. Services might still be starting up."
        echo "You can check the URL later with:"
        echo "gcloud run services list --project=$PROJECT_ID --region=$REGION --format='table(metadata.name,status.url)'"
    fi
}

# Run main function
main "$@"