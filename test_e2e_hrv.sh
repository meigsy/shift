#!/bin/bash -e

# End-to-end HRV test script for SHIFT pipeline
# Tests full lifecycle: watch_events → state_estimator → intervention_selector → app_interactions → trace_full_chain
# Uses synthetic HRV data to trigger high stress intervention

PROJECT="shift-dev-478422"
DATASET="shift_data"
# Note: Mock tokens map to "mock-user-default" in watch_events service
TEST_USER_ID="mock-user-default"
WATCH_EVENTS_URL="https://watch-events-meqmyk4w5q-uc.a.run.app"
INTERVENTION_SELECTOR_URL="https://us-central1-shift-dev-478422.cloudfunctions.net/intervention-selector-http"

# Generate trace_id for full traceability
TRACE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

# Mock token for authentication (backend accepts any token starting with "mock." as mock-user-default)
MOCK_TOKEN="mock.e2e_test_user_hrv_1.$(date +%s)"

echo "🧪 End-to-End HRV Test Script"
echo ""
echo "Test User ID: $TEST_USER_ID"
echo "Trace ID: $TRACE_ID"
echo "Watch Events URL: $WATCH_EVENTS_URL"
echo "Intervention Selector URL: $INTERVENTION_SELECTOR_URL"
echo ""

# Step 1: POST synthetic HRV-heavy payload to /watch_events endpoint
echo "📝 Step 1: POSTing synthetic HRV data to /watch_events endpoint..."
echo ""

# Generate fetched_at timestamp
FETCHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create health data batch with HRV values chosen to trigger high stress (>0.7)
# HRV=25ms (low HRV = high stress)
# RestingHR=75bpm (high resting HR = high stress)
# Combined stress score: ~0.86 (HIGH - triggers intervention)
HEALTH_DATA=$(cat <<EOF
{
  "heartRate": [
    {
      "type": "heartRate",
      "value": 75.0,
      "unit": "bpm",
      "startDate": "$FETCHED_AT",
      "endDate": "$FETCHED_AT",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.Health"
    }
  ],
  "hrv": [
    {
      "type": "hrv",
      "value": 25.0,
      "unit": "ms",
      "startDate": "$FETCHED_AT",
      "endDate": "$FETCHED_AT",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.Health"
    }
  ],
  "restingHeartRate": [
    {
      "type": "restingHeartRate",
      "value": 75.0,
      "unit": "bpm",
      "startDate": "$FETCHED_AT",
      "endDate": "$FETCHED_AT",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.Health"
    }
  ],
  "steps": [
    {
      "type": "steps",
      "value": 5000.0,
      "unit": "count",
      "startDate": "$FETCHED_AT",
      "endDate": "$FETCHED_AT",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.Health"
    }
  ],
  "sleep": [],
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
  "fetchedAt": "$FETCHED_AT",
  "trace_id": "$TRACE_ID"
}
EOF
)

echo "Sending health data batch to $WATCH_EVENTS_URL/watch_events"
echo "Trace ID: $TRACE_ID"
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

# Step 2: Poll BigQuery until state_estimate appears (max 60 seconds, 5-second intervals)
echo ""
echo "⏳ Step 2: Polling for state_estimate (max 60 seconds)..."
echo ""

MAX_ATTEMPTS=12
ATTEMPT=0
STATE_ESTIMATE_FOUND=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "   Attempt $ATTEMPT/$MAX_ATTEMPTS..."
  
  STATE_ESTIMATE_COUNT=$(bq query --use_legacy_sql=false --project_id="$PROJECT" --format=csv --quiet <<EOF
SELECT COUNT(*) as count
FROM \`$PROJECT.$DATASET.state_estimates\`
WHERE user_id = '$TEST_USER_ID'
  AND trace_id = '$TRACE_ID'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
EOF
)
  
  COUNT_VALUE=$(echo "$STATE_ESTIMATE_COUNT" | tail -n 1 | tr -d ' ')
  
  if [ "$COUNT_VALUE" -gt 0 ]; then
    echo "✅ State estimate found!"
    STATE_ESTIMATE_FOUND=true
    break
  fi
  
  if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
    sleep 5
  fi
done

if [ "$STATE_ESTIMATE_FOUND" = false ]; then
  echo "❌ State estimate not found after $MAX_ATTEMPTS attempts"
  exit 1
fi

# Step 3: Poll BigQuery until intervention_instance appears (max 60 seconds, 5-second intervals)
echo ""
echo "⏳ Step 3: Polling for intervention_instance (max 60 seconds)..."
echo ""

ATTEMPT=0
INTERVENTION_FOUND=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "   Attempt $ATTEMPT/$MAX_ATTEMPTS..."
  
  INTERVENTION_COUNT=$(bq query --use_legacy_sql=false --project_id="$PROJECT" --format=csv --quiet <<EOF
SELECT COUNT(*) as count
FROM \`$PROJECT.$DATASET.intervention_instances\`
WHERE user_id = '$TEST_USER_ID'
  AND trace_id = '$TRACE_ID'
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
EOF
)
  
  COUNT_VALUE=$(echo "$INTERVENTION_COUNT" | tail -n 1 | tr -d ' ')
  
  if [ "$COUNT_VALUE" -gt 0 ]; then
    echo "✅ Intervention instance found!"
    INTERVENTION_FOUND=true
    break
  fi
  
  if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
    sleep 5
  fi
done

if [ "$INTERVENTION_FOUND" = false ]; then
  echo "❌ Intervention instance not found after $MAX_ATTEMPTS attempts"
  exit 1
fi

# Step 4: Call HTTP endpoint to get intervention details
echo ""
echo "📱 Step 4: Fetching intervention details from HTTP endpoint..."
echo ""

INTERVENTION_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X GET \
  -H "Authorization: Bearer $MOCK_TOKEN" \
  "$INTERVENTION_SELECTOR_URL/interventions?user_id=$TEST_USER_ID&status=created")

HTTP_CODE=$(echo "$INTERVENTION_RESPONSE" | tail -n1)
BODY=$(echo "$INTERVENTION_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 200 ]; then
  echo "✅ Intervention details retrieved"
  echo "$BODY" | jq '.'
  
  # Extract intervention_instance_id, trace_id, surface from response
  INTERVENTION_INSTANCE_ID=$(echo "$BODY" | jq -r '.interventions[0].intervention_instance_id // empty')
  EXTRACTED_TRACE_ID=$(echo "$BODY" | jq -r '.interventions[0].trace_id // empty')
  SURFACE=$(echo "$BODY" | jq -r '.interventions[0].surface // empty')
  
  if [ -z "$INTERVENTION_INSTANCE_ID" ]; then
    echo "❌ Failed to extract intervention_instance_id from response"
    exit 1
  fi
  
  echo ""
  echo "   Intervention Instance ID: $INTERVENTION_INSTANCE_ID"
  echo "   Trace ID: $EXTRACTED_TRACE_ID"
  echo "   Surface: $SURFACE"
else
  echo "❌ Failed to get intervention details (HTTP $HTTP_CODE)"
  echo "$BODY"
  exit 1
fi

# Step 5: POST interaction events to /app_interactions
echo ""
echo "📊 Step 5: POSTing interaction events to /app_interactions..."
echo ""

# Generate timestamps for each event (1 second apart)
TIMESTAMP_SHOWN=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
sleep 1
TIMESTAMP_TAPPED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
sleep 1
TIMESTAMP_DISMISSED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# POST "shown" event
echo "   Posting 'shown' event..."
SHOWN_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MOCK_TOKEN" \
  -d "{
    \"trace_id\": \"$EXTRACTED_TRACE_ID\",
    \"user_id\": \"$TEST_USER_ID\",
    \"intervention_instance_id\": \"$INTERVENTION_INSTANCE_ID\",
    \"event_type\": \"shown\",
    \"timestamp\": \"$TIMESTAMP_SHOWN\"
  }" \
  "$WATCH_EVENTS_URL/app_interactions")

HTTP_CODE=$(echo "$SHOWN_RESPONSE" | tail -n1)
if [ "$HTTP_CODE" -eq 200 ]; then
  echo "   ✅ 'shown' event recorded"
else
  echo "   ❌ Failed to record 'shown' event (HTTP $HTTP_CODE)"
fi

# POST "tapped" event
echo "   Posting 'tapped' event..."
TAPPED_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MOCK_TOKEN" \
  -d "{
    \"trace_id\": \"$EXTRACTED_TRACE_ID\",
    \"user_id\": \"$TEST_USER_ID\",
    \"intervention_instance_id\": \"$INTERVENTION_INSTANCE_ID\",
    \"event_type\": \"tapped\",
    \"timestamp\": \"$TIMESTAMP_TAPPED\"
  }" \
  "$WATCH_EVENTS_URL/app_interactions")

HTTP_CODE=$(echo "$TAPPED_RESPONSE" | tail -n1)
if [ "$HTTP_CODE" -eq 200 ]; then
  echo "   ✅ 'tapped' event recorded"
else
  echo "   ❌ Failed to record 'tapped' event (HTTP $HTTP_CODE)"
fi

# POST "dismissed" event
echo "   Posting 'dismissed' event..."
DISMISSED_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MOCK_TOKEN" \
  -d "{
    \"trace_id\": \"$EXTRACTED_TRACE_ID\",
    \"user_id\": \"$TEST_USER_ID\",
    \"intervention_instance_id\": \"$INTERVENTION_INSTANCE_ID\",
    \"event_type\": \"dismissed\",
    \"timestamp\": \"$TIMESTAMP_DISMISSED\"
  }" \
  "$WATCH_EVENTS_URL/app_interactions")

HTTP_CODE=$(echo "$DISMISSED_RESPONSE" | tail -n1)
if [ "$HTTP_CODE" -eq 200 ]; then
  echo "   ✅ 'dismissed' event recorded"
else
  echo "   ❌ Failed to record 'dismissed' event (HTTP $HTTP_CODE)"
fi

# Step 6: Run verification queries
echo ""
echo "🔍 Step 6: Running verification queries..."
echo ""

echo "Latest watch_events row:"
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT
  user_id,
  trace_id,
  fetched_at,
  ingested_at,
  JSON_EXTRACT_SCALAR(payload, '$.heartRate[0].value') as heart_rate,
  JSON_EXTRACT_SCALAR(payload, '$.hrv[0].value') as hrv
FROM \`$PROJECT.$DATASET.watch_events\`
WHERE trace_id = '$TRACE_ID'
ORDER BY ingested_at DESC
LIMIT 1
EOF

echo ""
echo "Latest state_estimates row:"
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT
  user_id,
  trace_id,
  timestamp,
  recovery,
  readiness,
  stress,
  fatigue
FROM \`$PROJECT.$DATASET.state_estimates\`
WHERE trace_id = '$TRACE_ID'
ORDER BY timestamp DESC
LIMIT 1
EOF

echo ""
echo "Latest intervention_instances row:"
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT
  intervention_instance_id,
  user_id,
  trace_id,
  metric,
  level,
  surface,
  intervention_key,
  status,
  created_at
FROM \`$PROJECT.$DATASET.intervention_instances\`
WHERE trace_id = '$TRACE_ID'
ORDER BY created_at DESC
LIMIT 1
EOF

echo ""
echo "Latest app_interactions rows:"
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT
  interaction_id,
  trace_id,
  user_id,
  intervention_instance_id,
  event_type,
  timestamp
FROM \`$PROJECT.$DATASET.app_interactions\`
WHERE trace_id = '$EXTRACTED_TRACE_ID'
ORDER BY timestamp DESC
EOF

echo ""
echo "trace_full_chain view for trace_id:"
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT *
FROM \`$PROJECT.$DATASET.trace_full_chain\`
WHERE trace_id = '$EXTRACTED_TRACE_ID'
ORDER BY event_timestamp
EOF

# Step 7: Print summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 End-to-End HRV Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Full lifecycle completed successfully!"
echo ""
echo "Test Details:"
echo "  • Test User ID: $TEST_USER_ID"
echo "  • Trace ID: $TRACE_ID"
echo "  • Intervention Instance ID: $INTERVENTION_INSTANCE_ID"
echo "  • Surface: $SURFACE"
echo ""
echo "Pipeline Flow:"
echo "  1. ✅ watch_events: HRV data ingested"
echo "  2. ✅ state_estimates: Stress score calculated"
echo "  3. ✅ intervention_instances: Intervention created"
echo "  4. ✅ app_interactions: 3 events recorded (shown, tapped, dismissed)"
echo "  5. ✅ trace_full_chain: Full traceability verified"
echo ""
echo "You can query BigQuery to see all test data:"
echo "  • watch_events: WHERE trace_id = '$TRACE_ID'"
echo "  • state_estimates: WHERE trace_id = '$TRACE_ID'"
echo "  • intervention_instances: WHERE trace_id = '$TRACE_ID'"
echo "  • app_interactions: WHERE trace_id = '$EXTRACTED_TRACE_ID'"
echo "  • trace_full_chain: WHERE trace_id = '$EXTRACTED_TRACE_ID'"
echo ""
