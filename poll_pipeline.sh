#!/bin/bash

PROJECT="shift-dev-478422"
DATASET="shift_data"
TEST_USER_ID="mock-user-default"

echo "🔍 Polling pipeline for new data (user: $TEST_USER_ID)"
echo "Press Ctrl+C to stop"
echo ""

MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Poll #$ATTEMPT - $(date '+%H:%M:%S')"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check watch_events
  echo ""
  echo "1️⃣  watch_events:"
  WATCH_EVENT=$(bq query --use_legacy_sql=false --project_id=$PROJECT --format=json \
    "SELECT trace_id, fetched_at, hrv, heart_rate, ingested_at 
     FROM \`$PROJECT.$DATASET.watch_events\` 
     WHERE user_id = '$TEST_USER_ID' 
     ORDER BY ingested_at DESC 
     LIMIT 1" 2>/dev/null | jq -r '.[0] // empty')
  
  if [ -n "$WATCH_EVENT" ] && [ "$WATCH_EVENT" != "null" ]; then
    TRACE_ID=$(echo "$WATCH_EVENT" | jq -r '.trace_id // "N/A"')
    HRV=$(echo "$WATCH_EVENT" | jq -r '.hrv // "N/A"')
    HR=$(echo "$WATCH_EVENT" | jq -r '.heart_rate // "N/A"')
    INGESTED=$(echo "$WATCH_EVENT" | jq -r '.ingested_at // "N/A"')
    echo "   ✅ Latest: HRV=$HRV ms, HR=$HR bpm, trace_id=$TRACE_ID"
    echo "   📅 Ingested: $INGESTED"
  else
    echo "   ⏳ No data yet..."
  fi
  
  # Check state_estimates
  echo ""
  echo "2️⃣  state_estimates:"
  STATE_EST=$(bq query --use_legacy_sql=false --project_id=$PROJECT --format=json \
    "SELECT trace_id, timestamp, stress, fatigue, recovery, readiness 
     FROM \`$PROJECT.$DATASET.state_estimates\` 
     WHERE user_id = '$TEST_USER_ID' 
     ORDER BY timestamp DESC 
     LIMIT 1" 2>/dev/null | jq -r '.[0] // empty')
  
  if [ -n "$STATE_EST" ] && [ "$STATE_EST" != "null" ]; then
    TRACE_ID=$(echo "$STATE_EST" | jq -r '.trace_id // "N/A"')
    STRESS=$(echo "$STATE_EST" | jq -r '.stress // "N/A"')
    FATIGUE=$(echo "$STATE_EST" | jq -r '.fatigue // "N/A"')
    TIMESTAMP=$(echo "$STATE_EST" | jq -r '.timestamp // "N/A"')
    echo "   ✅ Latest: stress=$STRESS, fatigue=$FATIGUE, trace_id=$TRACE_ID"
    echo "   📅 Timestamp: $TIMESTAMP"
  else
    echo "   ⏳ No state estimate yet..."
  fi
  
  # Check intervention_instances
  echo ""
  echo "3️⃣  intervention_instances:"
  INTERVENTION=$(bq query --use_legacy_sql=false --project_id=$PROJECT --format=json \
    "SELECT intervention_instance_id, trace_id, intervention_key, metric, level, surface, status, created_at 
     FROM \`$PROJECT.$DATASET.intervention_instances\` 
     WHERE user_id = '$TEST_USER_ID' 
     ORDER BY created_at DESC 
     LIMIT 1" 2>/dev/null | jq -r '.[0] // empty')
  
  if [ -n "$INTERVENTION" ] && [ "$INTERVENTION" != "null" ]; then
    INTERVENTION_ID=$(echo "$INTERVENTION" | jq -r '.intervention_instance_id // "N/A"')
    TRACE_ID=$(echo "$INTERVENTION" | jq -r '.trace_id // "N/A"')
    KEY=$(echo "$INTERVENTION" | jq -r '.intervention_key // "N/A"')
    METRIC=$(echo "$INTERVENTION" | jq -r '.metric // "N/A"')
    LEVEL=$(echo "$INTERVENTION" | jq -r '.level // "N/A"')
    SURFACE=$(echo "$INTERVENTION" | jq -r '.surface // "N/A"')
    STATUS=$(echo "$INTERVENTION" | jq -r '.status // "N/A"')
    CREATED=$(echo "$INTERVENTION" | jq -r '.created_at // "N/A"')
    echo "   ✅ Latest: $KEY ($METRIC/$LEVEL) on $SURFACE"
    echo "   📋 Status: $STATUS, trace_id=$TRACE_ID"
    echo "   📅 Created: $CREATED"
  else
    echo "   ⏳ No intervention yet..."
  fi
  
  # Check app_interactions (latest)
  echo ""
  echo "4️⃣  app_interactions (latest):"
  INTERACTION=$(bq query --use_legacy_sql=false --project_id=$PROJECT --format=json \
    "SELECT event_type, timestamp, intervention_instance_id 
     FROM \`$PROJECT.$DATASET.app_interactions\` 
     WHERE user_id = '$TEST_USER_ID' 
     ORDER BY timestamp DESC 
     LIMIT 1" 2>/dev/null | jq -r '.[0] // empty')
  
  if [ -n "$INTERACTION" ] && [ "$INTERACTION" != "null" ]; then
    EVENT_TYPE=$(echo "$INTERACTION" | jq -r '.event_type // "N/A"')
    TIMESTAMP=$(echo "$INTERACTION" | jq -r '.timestamp // "N/A"')
    echo "   ✅ Latest: $EVENT_TYPE at $TIMESTAMP"
  else
    echo "   ⏳ No interactions yet..."
  fi
  
  echo ""
  sleep 3
done

echo ""
echo "⏱️  Polling complete (max attempts reached)"
