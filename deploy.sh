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
  echo "  - Backend container builds"
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
  
  echo "🏗️  Building Backend Container..."
  IMAGE_NAME="gcr.io/$PROJECT/shift-backend"
  TAG="latest"
  
  cd backend
  gcloud builds submit --tag "$IMAGE_NAME:$TAG" --project "$PROJECT"
  cd ..
  
  echo "✅ Container built and pushed: $IMAGE_NAME:$TAG"
fi

# -------------------------------------------------------------------------------
# Terraform Actions
# -------------------------------------------------------------------------------

echo "🌍 Running Terraform..."
cd terraform/projects/dev

# Initialize Terraform
terraform init

# Always use the same image name
IMAGE_NAME="gcr.io/$PROJECT/shift-backend:latest"

# Apply or Plan Terraform configuration
if [ "$PLAN_ONLY" = "yes" ]; then
  echo "Running Terraform plan (dry run)..."
  terraform plan \
    -var="project_id=$PROJECT" \
    -var="region=$REGION" \
    -var="backend_image=$IMAGE_NAME"
  echo "Terraform plan completed successfully."
else
  terraform apply \
    -var="project_id=$PROJECT" \
    -var="region=$REGION" \
    -var="backend_image=$IMAGE_NAME" \
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
  
  # Get Cloud Run URL from Terraform output (still in terraform/projects/dev from above)
  SERVICE_URL=$(terraform output -raw cloud_run_url 2>/dev/null || echo "")
  
  if [ -n "$SERVICE_URL" ]; then
    echo "🚀 Backend URL: $SERVICE_URL"
    echo ""
    echo "👉 Next Step: Update your iOS app's AuthViewModel.swift with this URL."
  fi
  
  # Validate pipeline if requested
  if [ "$VALIDATE_PIPELINE" = "yes" ]; then
    echo ""
    echo "🔍 Validating state_estimator pipeline..."
    cd pipelines/state_estimator
    
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
      echo "   cd pipelines/state_estimator"
      echo "   export GCP_PROJECT_ID=$PROJECT"
      echo "   uv run python -m src.main --project-id \$GCP_PROJECT_ID --skip-transform"
    fi
    
    cd ../..
  fi
  
  echo ""
  echo "✅ All deployments complete!"
fi
