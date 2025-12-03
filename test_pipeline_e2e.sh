#!/bin/bash -e

# End-to-end test script for SHIFT pipeline
# Uses the actual /watch_events HTTP endpoint (not direct BigQuery inserts)
# Tests: watch_events ingestion → state estimator → intervention selector → iOS polling

PROJECT="shift-dev-478422"
DATASET="shift_data"
TEST_USER_ID="mock-user-default"
WATCH_EVENTS_URL="https://watch-events-meqmyk4w5q-uc.a.run.app"

# Mock token for authentication (backend accepts any token starting with "mock." as mock-user-default)
MOCK_TOKEN="mock.test.token.$(date +%s)"

echo "🧪 End-to-End Pipeline Test (Using /watch_events Endpoint)"
echo ""
echo "Test User ID: $TEST_USER_ID"
echo "Watch Events URL: $WATCH_EVENTS_URL"
echo ""

# Step 1: POST health data to /watch_events endpoint
echo "📝 Step 1: POSTing health data to /watch_events endpoint..."
echo ""

# Generate fetched_at timestamp
FETCHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create health data batch matching HealthDataBatch schema
# NOTE: Values chosen to create HIGH STRESS (>0.7) automatically:
#   - HRV: 25ms (low HRV = high stress)
#   - Resting HR: 75 bpm (high resting HR = high stress)
#   Combined stress score: ~0.86 (HIGH - triggers intervention)
HEALTH_DATA=$(cat <<EOF
{
  "heartRate": [
    {
      "type": "heartRate",
      "value": 75.0,
      "unit": "bpm",
      "startDate": "2025-01-01T06:00:00Z",
      "endDate": "2025-01-01T06:05:00Z",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.Health"
    }
  ],
  "hrv": [
    {
      "type": "hrv",
      "value": 25.0,
      "unit": "ms",
      "startDate": "2025-01-01T06:00:00Z",
      "endDate": "2025-01-01T06:05:00Z",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.Health"
    }
  ],
  "restingHeartRate": [
    {
      "type": "restingHeartRate",
      "value": 75.0,
      "unit": "bpm",
      "startDate": "2025-01-01T06:00:00Z",
      "endDate": "2025-01-01T06:05:00Z",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.Health"
    }
  ],
  "steps": [
    {
      "type": "steps",
      "value": 5000.0,
      "unit": "count",
      "startDate": "2025-01-01T00:00:00Z",
      "endDate": "2025-01-01T23:59:59Z",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.Health"
    }
  ],
  "sleep": [
    {
      "stage": "DEEP",
      "startDate": "2025-01-01T04:00:00Z",
      "endDate": "2025-01-01T05:30:00Z",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.Health"
    }
  ],
  "walkingHeartRateAverage": [],
  "respiratoryRate": [],
  "oxygenSaturation": [],
  "vo2Max": [],
  "activeEnergy": [],
  "exerciseTime": [],
  "standTime": [],
  "timeInDaylight": [],
  "bodyMass": [],
  "bodyFatPercentage": [],
  "leanBodyMass": [],
  "workouts": [],
  "fetchedAt": "$FETCHED_AT"
}
EOF
)

echo "Sending health data batch to $WATCH_EVENTS_URL/watch_events"
echo ""

# POST to watch_events endpoint with mock token
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MOCK_TOKEN" \
  -d "$HEALTH_DATA" \
  "$WATCH_EVENTS_URL/watch_events")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 200 ]; then
  echo "✅ Health data posted successfully"
  echo "$BODY" | jq '.'
  SAMPLES_RECEIVED=$(echo "$BODY" | jq -r '.samples_received // 0')
  echo ""
  echo "   Samples received: $SAMPLES_RECEIVED"
else
  echo "❌ Failed to post health data (HTTP $HTTP_CODE)"
  echo "$BODY"
  exit 1
fi

echo ""
echo "⏳ Waiting 15 seconds for ingestion → state estimator → intervention selector to process..."
echo "   (State estimator automatically publishes to Pub/Sub, triggering intervention selector)"
sleep 15

# Step 2: Check if watch event was ingested into BigQuery
echo ""
echo "🔍 Step 2: Checking if watch event was ingested into BigQuery..."
echo ""

WATCH_EVENT_COUNT=$(bq query --use_legacy_sql=false --project_id="$PROJECT" --format=csv --quiet <<EOF
SELECT COUNT(*) as count
FROM \`$PROJECT.$DATASET.watch_events\`
WHERE user_id = '$TEST_USER_ID'
  AND fetched_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
EOF
)

COUNT_VALUE=$(echo "$WATCH_EVENT_COUNT" | tail -n 1 | tr -d ' ')

if [ "$COUNT_VALUE" -gt 0 ]; then
  echo "✅ Watch event ingested successfully! (count: $COUNT_VALUE)"
  echo ""
  echo "Latest watch event:"
  bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT
  user_id,
  fetched_at,
  ingested_at,
  JSON_EXTRACT_SCALAR(payload, '$.heartRate[0].value') as heart_rate,
  JSON_EXTRACT_SCALAR(payload, '$.hrv[0].value') as hrv
FROM \`$PROJECT.$DATASET.watch_events\`
WHERE user_id = '$TEST_USER_ID'
ORDER BY ingested_at DESC
LIMIT 1
EOF
else
  echo "⚠️  No watch event found in BigQuery (may need more wait time)"
fi

# Step 3: Check if state estimate was created
echo ""
echo "🔍 Step 3: Checking if state_estimate was created..."
echo ""

STATE_ESTIMATE_COUNT=$(bq query --use_legacy_sql=false --project_id="$PROJECT" --format=csv --quiet <<EOF
SELECT COUNT(*) as count
FROM \`$PROJECT.$DATASET.state_estimates\`
WHERE user_id = '$TEST_USER_ID'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
EOF
)

COUNT_VALUE=$(echo "$STATE_ESTIMATE_COUNT" | tail -n 1 | tr -d ' ')

if [ "$COUNT_VALUE" -gt 0 ]; then
  echo "✅ State estimate created! (count: $COUNT_VALUE)"
  echo ""
  echo "Latest state estimate:"
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
else
  echo "⚠️  No state estimate found (may need more wait time)"
  echo ""
  echo "Waiting additional 15 seconds for full pipeline processing..."
  sleep 15
fi

# Step 3: Check if intervention instance was created
# (State estimator automatically publishes to Pub/Sub, which triggers intervention selector)
echo ""
echo "🔍 Step 3: Checking if intervention instance was created..."
echo ""

INTERVENTION_COUNT=$(bq query --use_legacy_sql=false --project_id="$PROJECT" --format=csv --quiet <<EOF
SELECT COUNT(*) as count
FROM \`$PROJECT.$DATASET.intervention_instances\`
WHERE user_id = '$TEST_USER_ID'
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
EOF
)

COUNT_VALUE=$(echo "$INTERVENTION_COUNT" | tail -n 1 | tr -d ' ')

if [ "$COUNT_VALUE" -gt 0 ]; then
  echo "✅ Intervention instance created! (count: $COUNT_VALUE)"
  echo ""
  echo "Latest intervention:"
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
  
  echo ""
  echo "🎉 End-to-end pipeline test PASSED!"
  echo ""
  echo "📱 Next steps:"
  echo "   - The intervention is now in BigQuery with status 'created'"
  echo "   - iOS app should poll and display it within 60 seconds"
  echo "   - Check iOS app logs for polling and banner display"
else
  echo "⚠️  No intervention instance found"
  echo ""
  echo "This might happen if:"
  echo "  - Intervention selector hasn't processed yet (wait longer)"
  echo "  - Stress score didn't trigger an intervention"
fi

echo ""
echo "Test User ID: $TEST_USER_ID"
echo "You can query BigQuery to see all test data for this user."

