#!/bin/bash -e

# Script to check intervention selector logs with multiple methods

PROJECT="shift-dev-478422"

echo "🔍 Checking Intervention Selector Logs"
echo "======================================"
echo ""

echo "Method 1: Recent function executions..."
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=intervention-selector" \
  --limit=10 \
  --project="$PROJECT" \
  --format="table(timestamp,severity,textPayload)" \
  --freshness=15m 2>/dev/null || echo "No logs found with this method"

echo ""
echo "Method 2: All recent Cloud Function logs..."
gcloud logging read \
  "resource.type=cloud_function" \
  --limit=20 \
  --project="$PROJECT" \
  --format="table(timestamp,severity,textPayload)" \
  --freshness=15m 2>/dev/null | grep -i "intervention\|suppress\|preference" || echo "No relevant logs found"

echo ""
echo "Method 3: Check via Cloud Console..."
echo "   Visit: https://console.cloud.google.com/functions/details/us-central1/intervention-selector?project=$PROJECT"
echo "   Click on 'Logs' tab to see recent executions"

echo ""
echo "✅ Log check complete!"
echo ""
echo "💡 If no logs appear, the function may not have executed yet."
echo "   The Pub/Sub message was sent, but processing can take a few seconds."

