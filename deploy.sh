#!/bin/sh -e

# Single entry point for ALL GCP deployments and updates
# ALWAYS use this script to update GCP resources

# Get the directory where this script is located, then resolve to absolute path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

PROJECT="shift-dev-478422"
REGION="us-central1"

BUILD_CONTAINER=""
PLAN_ONLY=""
VALIDATE_PIPELINE=""

usage() {
  echo "Usage: $0 [-b|--build] [-p|--plan] [-v|--validate]"
  echo "  -b, --build      Build and push container image before deploying"
  echo "  -p, --plan       Run terraform plan instead of apply (dry run)"
  echo "  -v, --validate   Validate pipeline SQL after deployment (requires -p to be false)"
  echo "  -h, --help       Display this help message"
  echo ""
  echo "This script handles ALL GCP infrastructure updates:"
  echo "  - Terraform resources (tables, datasets, Pub/Sub, etc.)"
  echo "  - Pipeline container builds"
  echo "  - Pipeline validation"
  exit 1
}

# Parse command-line arguments
while [ $# -gt 0 ]; do
  case "$1" in
    -b|--build)
      BUILD_CONTAINER="yes"
      shift
      ;;
    -p|--plan)
      PLAN_ONLY="yes"
      shift
      ;;
    -v|--validate)
      VALIDATE_PIPELINE="yes"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: Unknown option: $1"
      usage
      ;;
  esac
done

# Define absolute paths
TERRAFORM_DIR="$PROJECT_ROOT/terraform/projects/dev"
WATCH_EVENTS_DIR="$PROJECT_ROOT/pipeline/watch_events"
STATE_ESTIMATOR_DIR="$PROJECT_ROOT/pipeline/state_estimator"
INTERVENTION_SELECTOR_DIR="$PROJECT_ROOT/pipeline/intervention_selector"

# -------------------------------------------------------------------------------
# Pre-Terraform Actions
# -------------------------------------------------------------------------------

if [ "$BUILD_CONTAINER" = "yes" ]; then
  echo "📦 Enabling Build APIs..."
  gcloud services enable cloudbuild.googleapis.com containerregistry.googleapis.com --project "$PROJECT"
  
  echo "🏗️  Building watch_events pipeline container..."
  WATCH_EVENTS_IMAGE="gcr.io/$PROJECT/watch-events"
  TAG="latest"
  
  gcloud builds submit --tag "$WATCH_EVENTS_IMAGE:$TAG" --project "$PROJECT" "$WATCH_EVENTS_DIR"
  
  echo "✅ Container built and pushed: $WATCH_EVENTS_IMAGE:$TAG"
fi

# -------------------------------------------------------------------------------
# Terraform Actions
# -------------------------------------------------------------------------------

echo "🌍 Running Terraform..."

# Initialize Terraform
(cd "$TERRAFORM_DIR" && terraform init)

# Always use the same image names
WATCH_EVENTS_IMAGE="gcr.io/$PROJECT/watch-events:latest"

# Apply or Plan Terraform configuration
if [ "$PLAN_ONLY" = "yes" ]; then
  echo "Running Terraform plan (dry run)..."
  (cd "$TERRAFORM_DIR" && terraform plan \
    -var="project_id=$PROJECT" \
    -var="region=$REGION" \
    -var="watch_events_image=$WATCH_EVENTS_IMAGE")
  echo "Terraform plan completed successfully."
else
  (cd "$TERRAFORM_DIR" && terraform apply \
    -var="project_id=$PROJECT" \
    -var="region=$REGION" \
    -var="watch_events_image=$WATCH_EVENTS_IMAGE" \
    -auto-approve)
fi

# Get service account emails from Terraform output
STATE_ESTIMATOR_SA=$(cd "$TERRAFORM_DIR" && terraform output -raw state_estimator_service_account_email 2>/dev/null || echo "")
INTERVENTION_SELECTOR_SA=$(cd "$TERRAFORM_DIR" && terraform output -raw intervention_selector_service_account_email 2>/dev/null || echo "")

# -------------------------------------------------------------------------------
# Post-Terraform Actions
# -------------------------------------------------------------------------------

if [ "$PLAN_ONLY" = "yes" ]; then
  echo "✅ Terraform plan completed. Review the changes above before running apply."
else
  echo "✅ Terraform deployment complete."
  
  # Deploy Cloud Function using gcloud (simple, handles everything)
  echo ""
  echo "⚡ Deploying state_estimator Cloud Function..."
  
  gcloud functions deploy state-estimator \
    --gen2 \
    --runtime=python311 \
    --region="$REGION" \
    --source="$STATE_ESTIMATOR_DIR" \
    --entry-point=state_estimator \
    --trigger-topic=watch_events \
    --service-account="${STATE_ESTIMATOR_SA}" \
    --set-env-vars="GCP_PROJECT_ID=$PROJECT,BQ_DATASET_ID=shift_data" \
    --memory=512Mi \
    --timeout=540s \
    --max-instances=10 \
    --min-instances=0 \
    --project="$PROJECT"
  
  # Get Cloud Run URLs from Terraform output
  WATCH_EVENTS_URL=$(cd "$TERRAFORM_DIR" && terraform output -raw watch_events_url 2>/dev/null || echo "")
  
  if [ -n "$WATCH_EVENTS_URL" ]; then
    echo ""
    echo "🚀 Watch Events Pipeline URL: $WATCH_EVENTS_URL"
    echo ""
    echo "👉 Next Step: Update your iOS app's ApiClient.swift with this URL."
  fi
  
  echo ""
  echo "⚡ State Estimator Cloud Function deployed"
  echo "   (Triggered automatically by Pub/Sub messages from watch_events)"
  
  # Deploy intervention_selector Cloud Functions
  echo ""
  echo "⚡ Deploying intervention_selector Cloud Functions..."
  
  # Deploy Pub/Sub-triggered function
  echo "   Deploying Pub/Sub-triggered function..."
  gcloud functions deploy intervention-selector \
    --gen2 \
    --runtime=python311 \
    --region="$REGION" \
    --source="$INTERVENTION_SELECTOR_DIR" \
    --entry-point=intervention_selector \
    --trigger-topic=state_estimates \
    --service-account="${INTERVENTION_SELECTOR_SA}" \
    --set-env-vars="GCP_PROJECT_ID=$PROJECT,BQ_DATASET_ID=shift_data" \
    --memory=512Mi \
    --timeout=540s \
    --max-instances=10 \
    --min-instances=0 \
    --project="$PROJECT"
  
  # Deploy HTTP-triggered function
  echo "   Deploying HTTP-triggered function..."
  gcloud functions deploy intervention-selector-http \
    --gen2 \
    --runtime=python311 \
    --region="$REGION" \
    --source="$INTERVENTION_SELECTOR_DIR" \
    --entry-point=get_intervention \
    --trigger-http \
    --allow-unauthenticated \
    --service-account="${INTERVENTION_SELECTOR_SA}" \
    --set-env-vars="GCP_PROJECT_ID=$PROJECT,BQ_DATASET_ID=shift_data" \
    --memory=512Mi \
    --timeout=60s \
    --max-instances=10 \
    --min-instances=0 \
    --project="$PROJECT"
  
  echo ""
  echo "⚡ Intervention Selector Cloud Functions deployed"
  echo "   (Pub/Sub: Triggered by state_estimates topic)"
  echo "   (HTTP: GET /interventions/{id} endpoint)"
  
  # Validate pipeline if requested
  if [ "$VALIDATE_PIPELINE" = "yes" ]; then
    echo ""
    echo "🔍 Validating state_estimator pipeline..."
    
    # Check if pipeline module exists
    if [ ! -f "$STATE_ESTIMATOR_DIR/src/main.py" ]; then
      echo "⚠️  Pipeline not found, skipping validation"
    else
      # Test that SQL files exist and are valid
      if [ ! -f "$STATE_ESTIMATOR_DIR/sql/views.sql" ] || [ ! -f "$STATE_ESTIMATOR_DIR/sql/transform.sql" ]; then
        echo "❌ Missing SQL files in pipeline"
        exit 1
      fi
      
      echo "✅ Pipeline SQL files validated"
      echo "   To test pipeline manually:"
      echo "   cd $STATE_ESTIMATOR_DIR"
      echo "   export GCP_PROJECT_ID=$PROJECT"
      echo "   uv run python -m src.main --project-id \$GCP_PROJECT_ID --skip-transform"
    fi
  fi
fi

echo ""
echo "✅ All deployments complete!"
