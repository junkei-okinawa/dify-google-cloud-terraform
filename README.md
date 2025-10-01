# Terraform for Dify on Google Cloud

![Google Cloud](https://img.shields.io/badge/Google%20Cloud-4285F4?logo=google-cloud&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-1.9.5-blue.svg)


![Dify GCP Architecture](images/dify-google-cloud-architecture.png)

<a href="./README_ja.md"><img alt="日本語のREADME" src="https://img.shields.io/badge/日本語-d9d9d9"></a>

> [!NOTE]
> - Dify v1.0.0 (and later) is supported now! Try it and give us feedbacks!!
> - If you fail to install any plugin, try several times and succeed in many cases.

## Overview
This repository allows you to automatically set up Google Cloud resources using Terraform and deploy Dify in a highly available configuration.

## Features
- Serverless hosting
- Auto-scaling
- Data persistence

## Prerequisites
- Google Cloud account
- Terraform installed
- gcloud CLI installed

### Enable Required APIs

Enable the Google Cloud APIs required for Dify deployment:

```sh
# Set your project ID (example: your-project-id)
export PROJECT_ID="your-project-id"

# Enable required APIs in batch
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
  --project=$PROJECT_ID
```

Verify enabled APIs:
```sh
gcloud services list --enabled --project=$PROJECT_ID --filter="name:(artifactregistry OR compute OR servicenetworking OR redis OR vpcaccess OR run OR storage OR sqladmin OR file OR cloudbuild OR containerregistry)" --format="table(name,title)"
```

### Create and Configure Terraform State Bucket

Create a GCS bucket for storing Terraform state files and automatically update the configuration:

```sh
# Create GCS bucket for Terraform state (skip if already exists)
export BUCKET_NAME="${PROJECT_ID}-terraform-state-dify"

# Check bucket existence and create if needed
if ! gsutil ls -p $PROJECT_ID gs://$BUCKET_NAME 2>/dev/null; then
    echo "Creating bucket: gs://$BUCKET_NAME"
    gsutil mb -p $PROJECT_ID -c STANDARD -l asia-northeast1 gs://$BUCKET_NAME
else
    echo "Bucket already exists: gs://$BUCKET_NAME"
fi

# Automatically update bucket name in provider.tf
cd terraform/environments/dev
sed -i.bak "s/your-tfstate-bucket/$BUCKET_NAME/g" provider.tf

# Verify the changes
echo "Updated provider.tf:"
grep -n "bucket.*=" provider.tf
```

Verify bucket creation:
```sh
gsutil ls -p $PROJECT_ID | grep terraform-state-dify
```

## Configuration
- Set environment-specific values in the `terraform/environments/dev/terraform.tfvars` file.

> [!WARNING]
> **Security Alert: Handling `terraform.tfvars`**
> The `terraform/environments/dev/terraform.tfvars` file in this repository is a **template only**. Populate it locally with your actual configuration (project ID, secrets, secure password).
>
> **Do NOT commit `terraform.tfvars` containing sensitive data to Git.** This poses a significant security risk.
>
> Add `*.tfvars` to your `.gitignore` file immediately to prevent accidental commits. For secure secret management, use environment variables (`TF_VAR_...`) or tools like Google Secret Manager.

- The GCS bucket for managing Terraform state will be created and configured using the automation commands above. For manual setup, create a GCS bucket and replace "your-tfstate-bucket" in the `terraform/environments/dev/provider.tf` file with your bucket name.

## Getting Started
1. Clone the repository:
    ```sh
    git clone https://github.com/DeNA/dify-google-cloud-terraform.git
    ```

2. Initialize Terraform:
    ```sh
    cd terraform/environments/dev
    terraform init
    ```

3. Make Artifact Registry repository:
    ```sh
    terraform apply -target=module.registry
    ```

4. Build & push container images:
    ```sh
    cd ../../..
    sh ./docker/cloudbuild.sh <your-project-id> <your-region>
    ```
    You can also specify a version of the dify-api image.
    ```sh
    sh ./docker/cloudbuild.sh <your-project-id> <your-region> <dify-api-version>
    ```
    If no version is specified, the latest version is used by default.

5. Terraform plan:
    ```sh
    cd terraform/environments/dev
    terraform plan
    ```

6. Terraform apply:
    ```sh
    terraform apply
    ```

## Post-Deployment Verification

### Check Dify Web Application URL

```sh
# List Cloud Run services and their URLs
gcloud run services list \
  --project=$PROJECT_ID \
  --region=asia-northeast1 \
  --format="table(metadata.name,status.url)"
```

### Access Dify

```sh
# Get Dify main service URL
DIFY_URL=$(gcloud run services describe dify-service \
  --project=$PROJECT_ID \
  --region=asia-northeast1 \
  --format="value(status.url)")

echo "Dify Web Application URL: $DIFY_URL"
echo "Access in browser: $DIFY_URL"

# Open URL directly in browser (macOS)
open $DIFY_URL
```

### Check Service Status

```sh
# Check detailed status of all Cloud Run services
gcloud run services list \
  --project=$PROJECT_ID \
  --region=asia-northeast1 \
  --format="table(metadata.name,status.url,status.conditions[0].type,status.conditions[0].status)"
```

## Cleanup

### Automated Cleanup Script (Recommended)
Use the following automated script for complete resource deletion:

```sh
# Grant execute permission to the script (first time only)
chmod +x cleanup-resources.sh

# Run resource cleanup
./cleanup-resources.sh <your-project-id>
```

This script automatically performs the following operations:
1. Delete Cloud SQL databases
2. Delete Cloud SQL instance
3. Delete Cloud Storage bucket
4. Delete VPC Peering
5. Auto-detect and delete default routes
6. Delete VPC network
7. Run terraform destroy

### Manual Cleanup (If script is not available)
If the script cannot be used, execute the following commands in order:

```sh
# Set environment variable
export PROJECT_ID="your-project-id"

# 1. Delete Cloud SQL databases
gcloud sql databases delete dify --instance=postgres-instance --project=$PROJECT_ID --quiet
gcloud sql databases delete dify_plugin --instance=postgres-instance --project=$PROJECT_ID --quiet

# 2. Delete Cloud SQL instance
gcloud sql instances delete postgres-instance --project=$PROJECT_ID --quiet

# 3. Delete Cloud Storage
gsutil rm -r "gs://${PROJECT_ID}_dify"

# 4. Delete VPC Peering
gcloud compute networks peerings delete servicenetworking-googleapis-com --network=dify-vpc --project=$PROJECT_ID --quiet

# 5. Delete VPC network
# Delete default routes first if they exist
gcloud compute routes list --filter="network:dify-vpc AND name~default-route" --project=$PROJECT_ID --format="value(name)" | xargs -I {} gcloud compute routes delete {} --project=$PROJECT_ID --quiet
gcloud compute networks delete dify-vpc --project=$PROJECT_ID --quiet

# 6. Terraform destroy
cd terraform/environments/dev
terraform destroy -auto-approve
```

## References
- [Dify](https://dify.ai/)
- [GitHub](https://github.com/langgenius/dify)

## License
This software is licensed under the MIT License. See the LICENSE file for more details.
