# Terraform Infrastructure for SHIFT Auth Backend

This directory contains Terraform configuration for the SHIFT authentication backend infrastructure in the development environment.

## Resources Created

- **APIs Enabled**:
  - Identity Platform (`identitytoolkit.googleapis.com`)
  - Cloud Run (`run.googleapis.com`)
  - IAM (`iam.googleapis.com`)
  - Secret Manager (`secretmanager.googleapis.com`)

- **Identity Platform**:
  - Identity Platform enabled for the project
  - Apple configured as OIDC provider

- **Cloud Run Service**:
  - Service name: `shift-backend`
  - Service account: `shift-backend-sa`
  - Public access (unauthenticated) - auth handled in application

- **Secret Manager**:
  - Reference to Apple private key secret (must be created separately)

## Required Variables

Create a `terraform.tfvars` file with the following variables:

```hcl
project_id                    = "shift-dev"
region                        = "us-central1"
apple_team_id                 = "YOUR_APPLE_TEAM_ID"
apple_client_id               = "com.shift.ios-app"
apple_key_id                  = "YOUR_APPLE_KEY_ID"
apple_client_secret           = "YOUR_APPLE_CLIENT_SECRET"  # Optional, for OIDC config
apple_private_key_secret_id   = "apple-private-key"
identity_platform_api_key     = "YOUR_IDENTITY_PLATFORM_API_KEY"
backend_image                 = "gcr.io/shift-dev/shift-backend:latest"
```

## Setup Steps

### 1. Create Apple Private Key Secret

Before running Terraform, create the Apple private key secret in Secret Manager:

```bash
echo -n "YOUR_APPLE_PRIVATE_KEY" | gcloud secrets create apple-private-key \
  --data-file=- \
  --project=shift-dev
```

### 2. Get Identity Platform API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Navigate to Identity Platform > Settings
3. Copy the Web API key

### 3. Initialize Terraform

```bash
cd terraform/projects/dev
terraform init
```

### 4. Plan and Apply

```bash
terraform plan
terraform apply
```

### 5. Get Cloud Run URL

After applying, get the Cloud Run URL:

```bash
terraform output cloud_run_url
```

Use this URL in your iOS app configuration.

## Apple Sign in with Apple Configuration

Before deploying, ensure you have:

1. **Apple Developer Account**:
   - Team ID
   - Service ID (matches `apple_client_id`)
   - Key ID and private key file

2. **Apple Service ID Configuration**:
   - Configured in Apple Developer Portal
   - Return URLs set to your Identity Platform redirect URLs
   - Sign in with Apple capability enabled

3. **Identity Platform OIDC Provider**:
   - Configured via Terraform (this file)
   - Client ID and secret match Apple Service ID

## Notes

- The Cloud Run service is publicly accessible (unauthenticated at the infrastructure level)
- Authentication is handled in the FastAPI application
- The service account has access to Secret Manager for Apple private key
- All sensitive values should be stored in Secret Manager or as Terraform variables marked as `sensitive`





