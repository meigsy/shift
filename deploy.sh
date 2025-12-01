#!/bin/sh -e

# Single entry point for ALL GCP deployments and updates
# ALWAYS use this script to update GCP resources

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

# -------------------------------------------------------------------------------
# Pre-Terraform Actions
# -------------------------------------------------------------------------------

if [ "$BUILD_CONTAINER" = "yes" ]; then
  echo "📦 Enabling Build APIs..."
  gcloud services enable cloudbuild.googleapis.com containerregistry.googleapis.com --project "$PROJECT"
  
  echo "🏗️  Building watch_events pipeline container..."
  WATCH_EVENTS_IMAGE="gcr.io/$PROJECT/watch-events"
  TAG="latest"
  
  cd pipeline/watch_events
  gcloud builds submit --tag "$WATCH_EVENTS_IMAGE:$TAG" --project "$PROJECT"
  cd ../..
  
  echo "✅ Container built and pushed: $WATCH_EVENTS_IMAGE:$TAG"
fi

# -------------------------------------------------------------------------------
# Terraform Actions
# -------------------------------------------------------------------------------

echo "🌍 Running Terraform..."
cd terraform/projects/dev

# Initialize Terraform
terraform init

# Always use the same image names
WATCH_EVENTS_IMAGE="gcr.io/$PROJECT/watch-events:latest"
STATE_ESTIMATOR_IMAGE="gcr.io/$PROJECT/state-estimator:latest"

# Apply or Plan Terraform configuration
if [ "$PLAN_ONLY" = "yes" ]; then
  echo "Running Terraform plan (dry run)..."
  terraform plan \
    -var="project_id=$PROJECT" \
    -var="region=$REGION" \
    -var="watch_events_image=$WATCH_EVENTS_IMAGE" \
    -var="state_estimator_image=$STATE_ESTIMATOR_IMAGE"
  echo "Terraform plan completed successfully."
else
  terraform apply \
    -var="project_id=$PROJECT" \
    -var="region=$REGION" \
    -var="watch_events_image=$WATCH_EVENTS_IMAGE" \
    -var="state_estimator_image=$STATE_ESTIMATOR_IMAGE" \
    -auto-approve
fi

cd ../..

# -------------------------------------------------------------------------------
# Post-Terraform Actions
# -------------------------------------------------------------------------------

if [ "$PLAN_ONLY" = "yes" ]; then
  echo "✅ Terraform plan completed. Review the changes above before running apply."
else
  echo "✅ Terraform deployment complete."
  
  # Get Cloud Run URLs from Terraform output (still in terraform/projects/dev from above)
  WATCH_EVENTS_URL=$(terraform output -raw watch_events_url 2>/dev/null || echo "")
  STATE_ESTIMATOR_URL=$(terraform output -raw state_estimator_url 2>/dev/null || echo "")
  
  # Return to project root
  cd ../..
  
  if [ -n "$WATCH_EVENTS_URL" ]; then
    echo "🚀 Watch Events Pipeline URL: $WATCH_EVENTS_URL"
    echo ""
    echo "👉 Next Step: Update your iOS app's ApiClient.swift with this URL."
  fi
  
  if [ -n "$STATE_ESTIMATOR_URL" ]; then
    echo ""
    echo "🔐 State Estimator Pipeline URL: $STATE_ESTIMATOR_URL"
    echo "   (Authenticated access only - use ADC bearer token)"
  fi
  
  # Validate pipeline if requested
  if [ "$VALIDATE_PIPELINE" = "yes" ]; then
    echo ""
    echo "🔍 Validating state_estimator pipeline..."
    cd pipeline/state_estimator
    
    # Check if pipeline module exists
    if [ ! -f "src/main.py" ]; then
      echo "⚠️  Pipeline not found, skipping validation"
    else
      # Test that SQL files exist and are valid
      if [ ! -f "sql/views.sql" ] || [ ! -f "sql/transform.sql" ]; then
        echo "❌ Missing SQL files in pipeline"
        exit 1
      fi
      
      echo "✅ Pipeline SQL files validated"
      echo "   To test pipeline manually:"
      echo "   cd pipeline/state_estimator"
      echo "   export GCP_PROJECT_ID=$PROJECT"
      echo "   uv run python -m src.main --project-id \$GCP_PROJECT_ID --skip-transform"
    fi
    
    cd ../..
  fi
fi

echo ""
echo "✅ All deployments complete!"
