# Manual HealthKit Test Guide

This guide explains how to test the SHIFT pipeline using real HealthKit data from your Apple Watch.

## Prerequisites

- iOS app installed and configured
- Apple Watch paired and collecting health data
- HealthKit authorization granted
- Access to BigQuery for verification queries

## Testing with Real HealthKit Data

### Step 1: Generate HRV Data

To trigger an intervention, you need HRV (Heart Rate Variability) data that indicates high stress:

1. **Ensure your Apple Watch is collecting HRV data**
   - HRV is typically measured during sleep or Breathe sessions
   - Check Health app → Browse → Heart → Heart Rate Variability

2. **Wait for recent HRV readings**
   - The app syncs data from the last 7 days on first sync
   - New data syncs automatically when HealthKit detects updates

### Step 2: Open the iOS App

1. Launch the SHIFT iOS app
2. Sign in with Apple (or use mock auth for testing)
3. Grant HealthKit permissions when prompted
4. The app will automatically sync health data to the backend

### Step 3: Wait for Banner

After syncing HRV data that indicates high stress:

1. The app polls for interventions every 60 seconds
2. If an intervention is created, a banner will appear
3. The banner shows the intervention title and body

### Step 4: Interact with the Intervention

1. **View the banner** (automatically recorded as "shown" event)
2. **Tap the banner** to see full details (recorded as "tapped" event)
3. **Dismiss the banner** (recorded as "dismissed" event)

Each interaction is automatically sent to the backend and stored in BigQuery.

## Verification Queries

After testing, run these BigQuery queries to verify the full pipeline:

### 1. Check watch_events for your user_id

```sql
SELECT
  user_id,
  trace_id,
  fetched_at,
  ingested_at,
  JSON_EXTRACT_SCALAR(payload, '$.hrv[0].value') as hrv_value,
  JSON_EXTRACT_SCALAR(payload, '$.hrv[0].unit') as hrv_unit
FROM `shift-dev-478422.shift_data.watch_events`
WHERE user_id = 'your-user-id'
ORDER BY ingested_at DESC
LIMIT 10;
```

### 2. Check state_estimates

```sql
SELECT
  user_id,
  trace_id,
  timestamp,
  recovery,
  readiness,
  stress,
  fatigue
FROM `shift-dev-478422.shift_data.state_estimates`
WHERE user_id = 'your-user-id'
ORDER BY timestamp DESC
LIMIT 10;
```

### 3. Check intervention_instances

```sql
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
FROM `shift-dev-478422.shift_data.intervention_instances`
WHERE user_id = 'your-user-id'
ORDER BY created_at DESC
LIMIT 10;
```

### 4. Check app_interactions

```sql
SELECT
  interaction_id,
  trace_id,
  user_id,
  intervention_instance_id,
  event_type,
  timestamp
FROM `shift-dev-478422.shift_data.app_interactions`
WHERE user_id = 'your-user-id'
ORDER BY timestamp DESC
LIMIT 10;
```

### 5. Query trace_full_chain with trace_id

First, get a trace_id from any of the above queries, then:

```sql
SELECT *
FROM `shift-dev-478422.shift_data.trace_full_chain`
WHERE trace_id = 'your-trace-id'
ORDER BY event_timestamp;
```

This shows the complete lifecycle:
- Raw biometrics from watch_events
- State scores from state_estimates
- Intervention metadata from intervention_instances
- User interaction events from app_interactions

## Full HRV → Intervention → Interaction Test

This section describes the complete manual test flow using real HealthKit data.

### Overview

The goal is to verify the entire pipeline works with real Apple Watch data:
1. Apple Watch collects HRV during sleep/Breathe
2. iOS app syncs HRV data to backend
3. State estimator calculates stress score
4. Intervention selector creates intervention if stress is high
5. iOS app displays intervention banner
6. User interacts with banner
7. Interactions are recorded in BigQuery

### Detailed Steps

#### 1. Prepare HealthKit Data

- **Sleep with Apple Watch**: Wear your watch during sleep to collect HRV readings
- **Or use Breathe app**: Open Breathe app on Apple Watch and complete a session
- **Check Health app**: Verify HRV data appears in Health app → Heart → Heart Rate Variability

#### 2. Sync Data via iOS App

- Open SHIFT iOS app
- Ensure you're signed in
- The app automatically syncs new HealthKit data
- Check app logs for sync confirmation messages

#### 3. Monitor Pipeline Processing

The pipeline processes data asynchronously:

- **watch_events** → Ingests immediately when app syncs
- **state_estimator** → Processes within ~10-20 seconds (triggered by Pub/Sub)
- **intervention_selector** → Processes within ~5-10 seconds (triggered by Pub/Sub)
- **iOS polling** → App checks for interventions every 60 seconds

#### 4. Verify Intervention Creation

Run BigQuery query to check if intervention was created:

```sql
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
FROM `shift-dev-478422.shift_data.intervention_instances`
WHERE user_id = 'your-user-id'
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY created_at DESC;
```

#### 5. Wait for Banner in iOS App

- The app polls every 60 seconds
- If an intervention exists with status='created', a banner appears
- Banner shows intervention title and body

#### 6. Interact with Banner

- **View**: Banner automatically triggers "shown" event
- **Tap**: Tap banner to see full details → triggers "tapped" event
- **Dismiss**: Swipe away or tap dismiss → triggers "dismissed" event

#### 7. Verify Interactions in BigQuery

```sql
SELECT
  interaction_id,
  trace_id,
  user_id,
  intervention_instance_id,
  event_type,
  timestamp
FROM `shift-dev-478422.shift_data.app_interactions`
WHERE user_id = 'your-user-id'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY timestamp DESC;
```

#### 8. View Complete Trace

Get the trace_id from the intervention_instance, then:

```sql
SELECT *
FROM `shift-dev-478422.shift_data.trace_full_chain`
WHERE trace_id = 'your-trace-id'
ORDER BY event_timestamp;
```

This shows the complete journey:
- Original HRV reading from Apple Watch
- State estimate with stress score
- Intervention selection and creation
- All user interaction events

### Troubleshooting

**No intervention created?**
- Check state_estimates: Is stress score > 0.7? (required for intervention)
- Check intervention_instances: Are there any with your user_id?
- Check app logs: Are there any errors during sync?

**Banner not appearing?**
- Check intervention_instances: Is status='created'?
- Check app logs: Is polling working? Are there API errors?
- Wait up to 60 seconds for next poll cycle

**Interactions not recorded?**
- Check app logs: Are interaction events being sent?
- Check BigQuery: Are rows appearing in app_interactions table?
- Verify trace_id matches between intervention and interaction

### Expected Timeline

- **T+0s**: iOS app syncs HRV data → watch_events ingested
- **T+10-20s**: state_estimator processes → state_estimates created
- **T+15-30s**: intervention_selector processes → intervention_instances created
- **T+0-60s**: iOS app polls → banner appears (depends on poll cycle)
- **T+immediate**: User interactions → app_interactions recorded

Total end-to-end latency: **20-90 seconds** (depending on poll cycle timing)
