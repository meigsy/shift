#!/bin/sh -e

# Test script for SHIFT pipeline end-to-end
# Inserts a test watch event and verifies the pipeline works

PROJECT="shift-dev-478422"
DATASET="shift_data"
TEST_USER_ID="test-user-$(date +%s)"

echo "🧪 Testing SHIFT Pipeline End-to-End"
echo ""
echo "Test User ID: $TEST_USER_ID"
echo ""

# Step 1: Insert test watch event into BigQuery
echo "📝 Step 1: Inserting test watch event into BigQuery..."
echo ""

bq query --use_legacy_sql=false --project_id="$PROJECT" <<EOF
INSERT INTO \`$PROJECT.$DATASET.watch_events\` (
  user_id,
  fetched_at,
  payload,
  ingested_at
)
VALUES (
  '$TEST_USER_ID',
  CURRENT_TIMESTAMP(),
  JSON '{"steps": [{"value": 5000, "startDate": "2025-01-01T00:00:00Z", "endDate": "2025-01-01T23:59:59Z"}], "hrv": [{"value": 45.0, "startDate": "2025-01-01T06:00:00Z", "endDate": "2025-01-01T06:05:00Z"}], "restingHeartRate": [{"value": 60.0, "startDate": "2025-01-01T06:00:00Z", "endDate": "2025-01-01T06:05:00Z"}], "sleep": [{"startDate": "2025-01-01T22:00:00Z", "endDate": "2025-01-02T06:00:00Z", "stage": "DEEP"}]}',
  CURRENT_TIMESTAMP()
)
EOF

if [ $? -eq 0 ]; then
  echo "✅ Test watch event inserted successfully"
else
  echo "❌ Failed to insert test watch event"
  exit 1
fi

echo ""
echo "⏳ Waiting 5 seconds for Pub/Sub message processing..."
sleep 5

# Step 2: Publish to watch_events Pub/Sub topic to trigger state_estimator
echo ""
echo "📤 Step 2: Publishing to watch_events Pub/Sub topic..."
echo ""

MESSAGE='{"user_id": "'$TEST_USER_ID'", "fetched_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'", "total_samples": 4}'

gcloud pubsub topics publish watch_events \
  --message="$MESSAGE" \
  --project="$PROJECT"

if [ $? -eq 0 ]; then
  echo "✅ Pub/Sub message published successfully"
else
  echo "❌ Failed to publish Pub/Sub message"
  exit 1
fi

echo ""
echo "⏳ Waiting 10 seconds for state_estimator to process..."
sleep 10

# Step 3: Check if state_estimate was created
echo ""
echo "🔍 Step 3: Checking if state_estimate was created..."
echo ""

bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT
  user_id,
  timestamp,
  recovery,
  readiness,
  stress,
  fatigue
FROM \`$PROJECT.$DATASET.state_estimates\`
WHERE user_id = '$TEST_USER_ID'
ORDER BY timestamp DESC
LIMIT 1
EOF

STATE_ESTIMATE_COUNT=$(bq query --use_legacy_sql=false --project_id="$PROJECT" --format=csv --quiet <<EOF
SELECT COUNT(*) as count
FROM \`$PROJECT.$DATASET.state_estimates\`
WHERE user_id = '$TEST_USER_ID'
EOF
)

# Extract just the number (skip header line)
COUNT_VALUE=$(echo "$STATE_ESTIMATE_COUNT" | tail -n 1 | tr -d ' ')

if [ "$COUNT_VALUE" -gt 0 ]; then
  echo ""
  echo "✅ State estimate created successfully! (count: $COUNT_VALUE)"
else
  echo ""
  echo "❌ No state estimate found for test user"
  exit 1
fi

# Step 4: Wait for intervention_selector to process
echo ""
echo "⏳ Waiting 10 seconds for intervention_selector to process..."
sleep 10

# Step 5: Check if intervention instance was created
echo ""
echo "🔍 Step 5: Checking if intervention instance was created..."
echo ""

bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT
  intervention_instance_id,
  user_id,
  metric,
  level,
  surface,
  intervention_key,
  status,
  created_at
FROM \`$PROJECT.$DATASET.intervention_instances\`
WHERE user_id = '$TEST_USER_ID'
ORDER BY created_at DESC
LIMIT 1
EOF

INTERVENTION_COUNT=$(bq query --use_legacy_sql=false --project_id="$PROJECT" --format=csv --quiet <<EOF
SELECT COUNT(*) as count
FROM \`$PROJECT.$DATASET.intervention_instances\`
WHERE user_id = '$TEST_USER_ID'
EOF
)

# Extract just the number (skip header line)
INTERVENTION_COUNT_VALUE=$(echo "$INTERVENTION_COUNT" | tail -n 1 | tr -d ' ')

if [ "$INTERVENTION_COUNT_VALUE" -gt 0 ]; then
  echo ""
  echo "✅ Intervention instance created successfully! (count: $INTERVENTION_COUNT_VALUE)"
  echo ""
  echo "🎉 End-to-end pipeline test PASSED!"
else
  echo ""
  echo "⚠️  No intervention instance found (this is OK if stress score doesn't trigger intervention)"
  echo ""
  echo "ℹ️  Pipeline processed successfully (state estimate created)"
fi

echo ""
echo "Test User ID: $TEST_USER_ID"
echo "You can query BigQuery to see all test data for this user."

