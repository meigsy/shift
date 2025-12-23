#!/bin/bash
set -e

PROJECT_ID="shift-dev-478422"
REGION="us-central1"
SERVICE_NAME="conversational-agent"

gcloud builds submit \
  --project=$PROJECT_ID \
  --tag gcr.io/$PROJECT_ID/$SERVICE_NAME:latest \
  .

gcloud run deploy $SERVICE_NAME \
  --project=$PROJECT_ID \
  --region=$REGION \
  --image gcr.io/$PROJECT_ID/$SERVICE_NAME:latest \
  --platform managed \
  --allow-unauthenticated \
  --memory 512Mi \
  --timeout 60s


