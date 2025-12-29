# Getting Started Flow - Deployment & Testing Plan

## Overview
This deployment includes:
1. **Backend changes**: Flow completion tracking, reset endpoint, saved interventions
2. **Infrastructure changes**: BigQuery schema update (payload field)
3. **iOS changes**: Flow event emission, UI updates

## Pre-Deployment Checklist

### Backend Code Changes
- ✅ Flow completion tracking (`flow_completed` events)
- ✅ Reset endpoint (`/user/reset`)
- ✅ Saved interventions query
- ✅ Selector dedup logic (version-aware)
- ✅ Context endpoint updates

### Infrastructure Changes
- ✅ BigQuery `app_interactions` schema: Added `payload` JSON field
- ⚠️ **IMPORTANT**: This is a schema change - existing rows will have NULL payload

### iOS Code Changes
- ✅ Flow completion emission
- ✅ About SHIFT / Reset UI
- ✅ Saved interventions UI

---

## Deployment Steps

### Step 1: Review Changes (Dry Run)

```bash
# Check Terraform plan (dry run)
./deploy.sh -p
```

**Expected changes:**
- BigQuery table `app_interactions` schema update (add `payload` field)

### Step 2: Deploy Backend & Infrastructure

```bash
# Build containers AND deploy infrastructure
./deploy.sh -b
```

**What this does:**
1. Builds `watch_events` container (includes new endpoints)
2. Builds `conversational_agent` container
3. Applies Terraform (updates BigQuery schema, Cloud Run services)
4. Deploys Cloud Functions (intervention_selector with dedup logic)

**Expected output:**
- ✅ Container builds complete
- ✅ Terraform apply successful
- ✅ Cloud Functions deployed
- ✅ Watch Events URL printed

### Step 3: Update iOS Configuration (if needed)

After deployment, note the `watch_events_url` from Terraform output:
```bash
cd terraform/projects/dev
terraform output watch_events_url
```

Update iOS app if URL changed (should be in Info.plist or build settings).

### Step 4: Build & Test iOS App

**Build in Xcode:**
1. Open `ios_app/ios_app.xcodeproj`
2. Select target device/simulator
3. Build (⌘+B)
4. Run (⌘+R)

---

## Testing Checklist

### Test 1: Fresh User - Getting Started Appears
**Steps:**
1. Sign in as a new user (or reset test user)
2. Open Home screen
3. **Expected**: `getting_started` intervention appears

**Verify in BigQuery:**
```sql
SELECT COUNT(*) 
FROM `shift-dev-478422.shift_data.intervention_instances`
WHERE user_id = '<your_user_id>'
  AND intervention_key = 'getting_started_v1'
  AND status = 'created'
```
Should be 1 (not multiple).

### Test 2: Complete Onboarding - Flow Completed Event
**Steps:**
1. Tap `getting_started` intervention
2. Go through onboarding
3. Tap "Start" button
4. **Expected**: GROW prompt appears, onboarding dismissed

**Verify in BigQuery:**
```sql
SELECT event_type, payload
FROM `shift-dev-478422.shift_data.app_interactions`
WHERE user_id = '<your_user_id>'
  AND event_type = 'flow_completed'
ORDER BY timestamp DESC
LIMIT 1
```
Should show: `{"flow_id": "getting_started", "flow_version": "v1"}`

**Verify completion check:**
```sql
-- This should return True (1 row) if completed
SELECT COUNT(*) > 0 as is_completed
FROM `shift-dev-478422.shift_data.app_interactions`
WHERE user_id = '<your_user_id>'
  AND event_type = 'flow_completed'
  AND JSON_EXTRACT_SCALAR(payload, '$.flow_id') = 'getting_started'
  AND JSON_EXTRACT_SCALAR(payload, '$.flow_version') = 'v1'
```

### Test 3: After Completion - Getting Started No Longer Appears
**Steps:**
1. After completing onboarding
2. Refresh Home screen (pull down)
3. **Expected**: `getting_started` does NOT appear in interventions list

**Verify in BigQuery:**
```sql
SELECT COUNT(*) 
FROM `shift-dev-478422.shift_data.intervention_instances`
WHERE user_id = '<your_user_id>'
  AND intervention_key = 'getting_started_v1'
  AND status = 'created'
```
Should be 0 or instance status changed (if user tapped/dismissed it).

### Test 4: About SHIFT Shows Flow Without Completion
**Steps:**
1. After completing onboarding
2. Open side panel
3. Tap "About SHIFT"
4. **Expected**: `getting_started` intervention appears
5. **Verify**: Complete onboarding again - should NOT mark as completed again (no duplicate `flow_completed`)

**Verify in BigQuery:**
```sql
SELECT event_type, payload, timestamp
FROM `shift-dev-478422.shift_data.app_interactions`
WHERE user_id = '<your_user_id>'
  AND event_type IN ('flow_requested', 'flow_completed')
ORDER BY timestamp DESC
LIMIT 5
```
Should show `flow_requested` but not a new `flow_completed`.

### Test 5: No Duplicate Getting Started Instances
**Steps:**
1. As a fresh user (before completion)
2. Trigger selector multiple times (wait for state estimates or manually trigger)
3. **Expected**: Only ONE `getting_started_v1` instance with `status='created'`

**Verify in BigQuery:**
```sql
SELECT intervention_instance_id, created_at, status
FROM `shift-dev-478422.shift_data.intervention_instances`
WHERE user_id = '<your_user_id>'
  AND intervention_key = 'getting_started_v1'
ORDER BY created_at DESC
```
Should be exactly 1 row with `status='created'` (before completion).

### Test 6: Reset Data - Getting Started Returns
**Steps:**
1. After completing onboarding
2. Open side panel
3. Tap "Reset my data"
4. Refresh Home screen
5. **Expected**: `getting_started` appears again

**Verify in BigQuery:**
```sql
-- Check reset event
SELECT event_type, payload, timestamp
FROM `shift-dev-478422.shift_data.app_interactions`
WHERE user_id = '<your_user_id>'
  AND event_type = 'flow_reset'
ORDER BY timestamp DESC
LIMIT 1
```
Should show: `{"scope": "all"}`

**Verify completion check returns False:**
```sql
-- Should return False (0 rows) after reset
SELECT COUNT(*) > 0 as is_completed
FROM (
  SELECT event_type, timestamp
  FROM `shift-dev-478422.shift_data.app_interactions`
  WHERE user_id = '<your_user_id>'
    AND event_type IN ('flow_completed', 'flow_reset')
    AND (
      JSON_EXTRACT_SCALAR(payload, '$.flow_id') = 'getting_started'
      OR JSON_EXTRACT_SCALAR(payload, '$.scope') = 'all'
    )
  ORDER BY timestamp DESC
  LIMIT 1
)
WHERE event_type = 'flow_completed'
```

### Test 7: Save Intervention
**Steps:**
1. Open any intervention detail view
2. Tap "Save" button
3. **Expected**: Button changes to "Saved"
4. Open side panel
5. **Expected**: Saved intervention appears in "Saved" section

**Verify in BigQuery:**
```sql
SELECT event_type, payload, timestamp
FROM `shift-dev-478422.shift_data.app_interactions`
WHERE user_id = '<your_user_id>'
  AND event_type = 'intervention_saved'
ORDER BY timestamp DESC
LIMIT 1
```
Should show intervention_key in payload.

### Test 8: Reset Clears Saved Interventions
**Steps:**
1. Save some interventions (Test 7)
2. Reset data (scope="all")
3. Open side panel → "Saved" section
4. **Expected**: Saved list is empty

**Verify in BigQuery:**
```sql
-- Check saved interventions query logic
WITH cte_reset AS (
  SELECT MAX(timestamp) as reset_timestamp
  FROM `shift-dev-478422.shift_data.app_interactions`
  WHERE user_id = '<your_user_id>'
    AND event_type = 'flow_reset'
    AND JSON_EXTRACT_SCALAR(payload, '$.scope') = 'all'
),
cte_events AS (
  SELECT
    event_type,
    JSON_EXTRACT_SCALAR(payload, '$.intervention_key') AS intervention_key,
    timestamp
  FROM `shift-dev-478422.shift_data.app_interactions`
  WHERE user_id = '<your_user_id>'
    AND event_type IN ('intervention_saved', 'intervention_unsaved')
)
SELECT cte_events.*
FROM cte_events
CROSS JOIN cte_reset
WHERE cte_events.event_type = 'intervention_saved'
  AND (cte_reset.reset_timestamp IS NULL OR cte_events.timestamp > cte_reset.reset_timestamp)
```
Should return 0 rows if reset happened after saves.

---

## Rollback Plan (if needed)

### If deployment fails:

**Rollback Terraform:**
```bash
cd terraform/projects/dev
terraform state list | grep app_interactions
terraform state show google_bigquery_table.app_interactions
# If needed, revert to previous state
terraform state rm google_bigquery_table.app_interactions
# Restore from backup or manual schema change
```

**Rollback containers:**
- Previous container versions remain available in GCR
- Update Terraform to point to previous image tag if needed

**Rollback iOS:**
- Git revert iOS changes
- Rebuild in Xcode

---

## Post-Deployment Verification

### Quick Health Checks

1. **Backend endpoints responding:**
```bash
# Get auth token
gcloud auth print-identity-token

# Test /context endpoint
curl -H "Authorization: Bearer <token>" \
  https://watch-events-<hash>-uc.a.run.app/context

# Should return: state_estimate, interventions, saved_interventions
```

2. **Check logs for errors:**
```bash
# Watch Events logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=watch-events" \
  --limit=50 --format=json --project=shift-dev-478422

# Intervention Selector logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=intervention-selector" \
  --limit=50 --format=json --project=shift-dev-478422
```

3. **Verify BigQuery schema:**
```sql
SELECT column_name, data_type, is_nullable
FROM `shift-dev-478422.shift_data.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'app_interactions'
ORDER BY ordinal_position
```
Should include `payload` as JSON, nullable.

---

## Success Criteria

✅ All tests pass
✅ No duplicate instances created
✅ Flow completion properly tracked
✅ Reset works as expected
✅ Saved interventions clear on reset
✅ No errors in logs
✅ iOS app builds and runs

---

## Next Steps After Deployment

1. Monitor logs for first 24 hours
2. Verify user flows in production
3. Iterate on backend/agent logic (now stable spine)
4. Add `getting_started_v2` to catalog when ready (no code changes needed)

