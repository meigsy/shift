#!/bin/sh -e

PROJECT="shift-dev-478422"
REGION="us-central1"

BUILD_CONTAINER=""
PLAN_ONLY=""

usage() {
  echo "Usage: $0 [-b|--build] [-p|--plan]"
  echo "  -b, --build    Build and push container image before deploying"
  echo "  -p, --plan     Run terraform plan instead of apply (dry run)"
  echo "  -h, --help     Display this help message"
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

# Apply or Plan Terraform configuration
if [ "$PLAN_ONLY" = "yes" ]; then
  echo "Running Terraform plan (dry run)..."
  terraform plan \
    -var="project_id=$PROJECT" \
    -var="region=$REGION"
  echo "Terraform plan completed successfully."
else
  # If building container, get the image tag to pass to Terraform
  if [ "$BUILD_CONTAINER" = "yes" ]; then
    IMAGE_NAME="gcr.io/$PROJECT/shift-backend:latest"
    terraform apply \
      -var="project_id=$PROJECT" \
      -var="region=$REGION" \
      -var="backend_image=$IMAGE_NAME" \
      -auto-approve
  else
    terraform apply \
      -var="project_id=$PROJECT" \
      -var="region=$REGION" \
      -auto-approve
  fi
fi

cd ../..

# -------------------------------------------------------------------------------
# Post-Terraform Actions
# -------------------------------------------------------------------------------

if [ "$PLAN_ONLY" = "yes" ]; then
  echo "Terraform plan completed. Review the changes above before running apply."
else
  echo "✅ Deployment complete."
  
  # Get Cloud Run URL from Terraform output
  SERVICE_URL=$(cd terraform/projects/dev && terraform output -raw cloud_run_url 2>/dev/null || echo "")
  if [ -n "$SERVICE_URL" ]; then
    echo "🚀 Backend URL: $SERVICE_URL"
    echo ""
    echo "👉 Next Step: Update your iOS app's AuthViewModel.swift with this URL."
  fi
fi
