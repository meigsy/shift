#!/bin/bash -e

# Script to trigger a state estimate that will cause the intervention selector to run
# This tests the suppression logic end-to-end

PROJECT="shift-dev-478422"
DATASET="shift_data"
USER_ID="mock-user-default"

echo "🔄 Triggering state estimate to test suppression logic..."
echo "   Project: $PROJECT"
echo "   User ID: $USER_ID"
echo ""

# Create a new state estimate with high stress (should trigger intervention selection)
# The selector will run and should suppress all interventions due to high annoyance rate

TRACE_ID=$(python3 -c "import uuid; print(uuid.uuid4())")

echo "📝 Creating state estimate with trace_id: $TRACE_ID"
echo ""

bq query --use_legacy_sql=false --project_id="$PROJECT" <<EOF
INSERT INTO \`$PROJECT.$DATASET.state_estimates\` (
  user_id,
  timestamp,
  trace_id,
  recovery,
  readiness,
  stress,
  fatigue
)
VALUES (
  '$USER_ID',
  CURRENT_TIMESTAMP(),
  '$TRACE_ID',
  0.5,
  0.6,
  0.8,  -- High stress (should trigger high-level intervention)
  0.3
)
EOF

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ State estimate created!"
  echo ""
  echo "📤 Publishing to Pub/Sub topic: state_estimates"
  
  # Publish to Pub/Sub to trigger the intervention selector
  gcloud pubsub topics publish state_estimates \
    --project="$PROJECT" \
    --message="{\"user_id\": \"$USER_ID\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    2>/dev/null || echo "⚠️  Note: Pub/Sub publish may require authentication. The state estimate is in BigQuery and can be processed manually."
  
  echo ""
  echo "⏳ Waiting 5 seconds for Cloud Function to process..."
  sleep 5
  
  echo ""
  echo "🔍 Checking if intervention was created (should be None if suppression works)..."
  bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT 
  intervention_instance_id,
  user_id,
  intervention_key,
  surface,
  created_at,
  status,
  trace_id
FROM \`$PROJECT.$DATASET.intervention_instances\`
WHERE trace_id = '$TRACE_ID'
ORDER BY created_at DESC
LIMIT 1
EOF
  
  echo ""
  echo "📊 Expected result:"
  echo "   - If suppression works: No intervention created (empty result)"
  echo "   - If suppression fails: Intervention created with intervention_key"
  echo ""
  echo "💡 Check Cloud Function logs for suppression messages:"
  echo "   gcloud functions logs read intervention-selector --limit=10 --project=$PROJECT"
else
  echo ""
  echo "❌ Failed to create state estimate"
  exit 1
fi

