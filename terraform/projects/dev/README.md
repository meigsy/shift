# Terraform Infrastructure for SHIFT Pipelines

This directory contains Terraform configuration for SHIFT pipeline infrastructure in the development environment.

## Resources Created

- **APIs Enabled**:
  - Identity Platform (`identitytoolkit.googleapis.com`)
  - Cloud Run (`run.googleapis.com`)
  - IAM (`iam.googleapis.com`)
  - Secret Manager (`secretmanager.googleapis.com`)
  - BigQuery (`bigquery.googleapis.com`)
  - Pub/Sub (`pubsub.googleapis.com`)
  - Firestore (`firestore.googleapis.com`)

- **Identity Platform**:
  - Identity Platform enabled for the project
  - Apple configured as OIDC provider

- **Cloud Run Services**:
  - `watch-events`: Public access (unauthenticated) - auth handled in application
    - Service account: `watch-events-sa`
    - Handles authentication and health data ingestion
  - `state-estimator`: Authenticated access only (least privilege)
    - Service account: `state-estimator-sa`
    - Accessible to authenticated project members (owners/editors) - no explicit IAM bindings needed
    - No public access (allUsers) - unauthenticated requests are blocked
    - Access via: `gcloud auth print-identity-token` bearer token

- **BigQuery**:
  - Dataset: `shift_data`
  - Tables: `watch_events`, `state_estimates`

- **Pub/Sub**:
  - Topic: `watch_events`

- **Secret Manager**:
  - Reference to Apple private key secret (must be created separately)

## Required Variables

Create a `terraform.tfvars` file with the following variables:

```hcl
project_id                      = "shift-dev"
region                          = "us-central1"
apple_team_id                   = "YOUR_APPLE_TEAM_ID"
apple_client_id                 = "com.shift.ios-app"
apple_key_id                    = "YOUR_APPLE_KEY_ID"
apple_client_secret             = "YOUR_APPLE_CLIENT_SECRET"  # Optional, for OIDC config
apple_private_key_secret_id     = "apple-private-key"
identity_platform_api_key       = "YOUR_IDENTITY_PLATFORM_API_KEY"
watch_events_image              = "gcr.io/shift-dev/watch-events:latest"
state_estimator_image           = "gcr.io/shift-dev/state-estimator:latest"
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

### 5. Get Cloud Run URLs

After applying, get the Cloud Run URLs:

```bash
terraform output watch_events_url
terraform output state_estimator_url
```

Use `watch_events_url` in your iOS app configuration. Use `state_estimator_url` with ADC bearer token for authenticated access.

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

- **watch-events**: Publicly accessible (unauthenticated at infrastructure level). Authentication is handled in the FastAPI application.
- **state-estimator**: Least privilege access - accessible to authenticated project members (owners/editors). No public access.
- Service accounts have appropriate permissions (BigQuery, Pub/Sub, Secret Manager as needed)
- All sensitive values should be stored in Secret Manager or as Terraform variables marked as `sensitive`
- Naming convention: Services use hyphenated names (e.g., `watch-events`, `state-estimator`) matching folder structure (e.g., `pipeline/watch_events/`)





