# SQL Validation Checklist

**Purpose**: Reference guide for manually validating SQL logic in BigQuery. Used during development and testing.

Manual validation steps to verify SQL logic works correctly in BigQuery.

## Prerequisites

- Access to BigQuery console for project `shift-dev-478422`
- Sample data in `watch_events` table (or ability to create test data)

---

## Step 1: Validate Input View Creation

### 1.1 Create/Update Views

```sql
-- Run the views.sql file in BigQuery
-- Source: pipeline/state_estimator/sql/views.sql
```

**Expected Result:**
- View `shift_data.v_state_estimator_input_v1` created/updated successfully
- View `shift_data.v_state_estimator_unprocessed_v1` created/updated successfully

### 1.2 Verify Input View Output

```sql
-- Check the input view extracts data correctly
SELECT 
  user_id,
  timestamp,
  hrv_value,
  resting_hr_value,
  sleep_minutes,
  workout_energy,
  steps_value
FROM `shift_data.v_state_estimator_input_v1`
LIMIT 10;
```

**Validation Checks:**
- [ ] View returns rows (or returns empty if no watch_events data)
- [ ] `hrv_value` is aggregated correctly (AVG from JSON array)
- [ ] `resting_hr_value` is aggregated correctly
- [ ] `sleep_minutes` sums only DEEP sleep stages
- [ ] `workout_energy` sums total energy from all workouts
- [ ] `steps_value` sums steps correctly
- [ ] NULL values handled correctly (COALESCE to 0.0)

### 1.3 Verify JSON Extraction

```sql
-- Verify JSON arrays are being extracted correctly
SELECT 
  user_id,
  fetched_at,
  JSON_EXTRACT_ARRAY(payload, '$.hrv') AS hrv_array,
  JSON_EXTRACT_ARRAY(payload, '$.restingHeartRate') AS resting_hr_array,
  JSON_EXTRACT_ARRAY(payload, '$.sleep') AS sleep_array,
  JSON_EXTRACT_ARRAY(payload, '$.workouts') AS workouts_array,
  JSON_EXTRACT_ARRAY(payload, '$.steps') AS steps_array
FROM `shift_data.watch_events`
WHERE JSON_EXTRACT_ARRAY(payload, '$.hrv') IS NOT NULL
LIMIT 1;
```

**Validation Checks:**
- [ ] JSON arrays are extracted correctly
- [ ] Arrays are not empty when data exists
- [ ] UNNEST works correctly on these arrays

---

## Step 2: Validate Unprocessed View

### 2.1 Check Unprocessed Filtering

```sql
-- Check unprocessed view filters correctly
SELECT 
  COUNT(*) as unprocessed_count
FROM `shift_data.v_state_estimator_unprocessed_v1`;
```

**Expected Result:**
- If `state_estimates` table is empty: returns all input records
- If `state_estimates` has records: only returns new/unprocessed records

### 2.2 Verify LEFT JOIN Logic

```sql
-- Verify LEFT JOIN excludes processed records
SELECT 
  input.user_id,
  input.timestamp,
  CASE 
    WHEN output.user_id IS NOT NULL THEN 'PROCESSED'
    ELSE 'UNPROCESSED'
  END as status
FROM `shift_data.v_state_estimator_input_v1` input
LEFT JOIN `shift_data.state_estimates` output
  ON input.user_id = output.user_id
  AND input.timestamp = output.timestamp
ORDER BY input.timestamp DESC
LIMIT 20;
```

**Validation Checks:**
- [ ] Records in `state_estimates` are marked as 'PROCESSED'
- [ ] Records not in `state_estimates` are marked as 'UNPROCESSED'
- [ ] Unprocessed view only returns 'UNPROCESSED' records

---

## Step 3: Validate Transform Logic

### 3.1 Test Transform SQL Manually

```sql
-- Run a test transform query (without INSERT) to see what would be inserted
WITH cte_unprocessed AS (
  SELECT
    user_id,
    timestamp,
    hrv_value,
    resting_hr_value,
    sleep_minutes,
    sleep_sample_count,
    workout_energy,
    workout_duration,
    steps_value
  FROM `shift_data.v_state_estimator_unprocessed_v1`
  LIMIT 10  -- Test with limited rows
),
cte_normalized_metrics AS (
  SELECT
    user_id,
    timestamp,
    LEAST(1.0, GREATEST(0.0, (hrv_value - 20.0) / 40.0)) AS normalized_hrv,
    LEAST(1.0, GREATEST(0.0, (80.0 - resting_hr_value) / 30.0)) AS normalized_resting_hr,
    LEAST(1.0, sleep_minutes / 480.0) AS normalized_sleep,
    LEAST(1.0, workout_energy / 1000.0) AS normalized_workout_intensity,
    LEAST(1.0, steps_value / 10000.0) AS normalized_activity
  FROM cte_unprocessed
),
cte_state_scores AS (
  SELECT
    user_id,
    timestamp,
    (
      (normalized_hrv * 0.4) +
      (normalized_resting_hr * 0.3) +
      (normalized_sleep * 0.3)
    ) AS recovery,
    (
      (
        (normalized_hrv * 0.4) +
        (normalized_resting_hr * 0.3) +
        (normalized_sleep * 0.3)
      ) * 0.7 +
      (normalized_activity * 0.3)
    ) AS readiness,
    (
      ((1.0 - normalized_hrv) * 0.6) +
      ((1.0 - normalized_resting_hr) * 0.4)
    ) AS stress,
    (
      ((1.0 - normalized_sleep) * 0.5) +
      (normalized_workout_intensity * 0.3) +
      ((1.0 - normalized_activity) * 0.2)
    ) AS fatigue
  FROM cte_normalized_metrics
)
SELECT
  user_id,
  timestamp,
  recovery,
  readiness,
  stress,
  fatigue,
  CASE
    WHEN recovery BETWEEN 0 AND 1 THEN 'VALID'
    ELSE 'INVALID'
  END as recovery_valid,
  CASE
    WHEN readiness BETWEEN 0 AND 1 THEN 'VALID'
    ELSE 'INVALID'
  END as readiness_valid,
  CASE
    WHEN stress BETWEEN 0 AND 1 THEN 'VALID'
    ELSE 'INVALID'
  END as stress_valid,
  CASE
    WHEN fatigue BETWEEN 0 AND 1 THEN 'VALID'
    ELSE 'INVALID'
  END as fatigue_valid
FROM cte_state_scores;
```

**Validation Checks:**
- [ ] All scores (recovery, readiness, stress, fatigue) are between 0 and 1
- [ ] No NULL values in calculated scores
- [ ] Scores make logical sense (e.g., high HRV = higher recovery)
- [ ] Normalization works correctly (HRV 60+ should give max normalized_hrv = 1.0)

### 3.2 Test Edge Cases

#### 3.2.1 Missing Data (NULL values)

```sql
-- Test with NULL values in input
SELECT
  user_id,
  timestamp,
  COALESCE(hrv_value, 0.0) AS hrv_value,
  COALESCE(resting_hr_value, 0.0) AS resting_hr_value,
  COALESCE(sleep_minutes, 0.0) AS sleep_minutes
FROM `shift_data.v_state_estimator_input_v1`
WHERE hrv_value IS NULL
  OR resting_hr_value IS NULL
LIMIT 5;
```

**Validation Checks:**
- [ ] NULL values are handled gracefully (COALESCE to 0.0)
- [ ] Calculations don't break with NULL values

#### 3.2.2 Extreme Values

```sql
-- Test normalization with extreme values
SELECT
  hrv_value,
  LEAST(1.0, GREATEST(0.0, (hrv_value - 20.0) / 40.0)) AS normalized_hrv
FROM `shift_data.v_state_estimator_input_v1`
WHERE hrv_value > 60 OR hrv_value < 20
LIMIT 5;
```

**Validation Checks:**
- [ ] Values > 60 are clamped to 1.0 (LEAST)
- [ ] Values < 20 are clamped to 0.0 (GREATEST)
- [ ] No scores exceed 0-1 range

---

## Step 4: Test Full Pipeline Execution

### 4.1 Run Transform (Insert into state_estimates)

```sql
-- Run the full transform.sql file
-- Source: pipeline/state_estimator/sql/transform.sql
```

**Expected Result:**
- Rows inserted into `shift_data.state_estimates` table
- Number of rows matches unprocessed records

### 4.2 Verify Inserted Data

```sql
-- Check inserted records
SELECT
  user_id,
  timestamp,
  recovery,
  readiness,
  stress,
  fatigue,
  -- Verify all scores are valid
  CASE
    WHEN recovery BETWEEN 0 AND 1 
     AND readiness BETWEEN 0 AND 1
     AND stress BETWEEN 0 AND 1
     AND fatigue BETWEEN 0 AND 1
    THEN 'VALID'
    ELSE 'INVALID'
  END as all_scores_valid
FROM `shift_data.state_estimates`
ORDER BY timestamp DESC
LIMIT 20;
```

**Validation Checks:**
- [ ] All scores are between 0 and 1
- [ ] No NULL values in scores
- [ ] User_id and timestamp match input data
- [ ] Records are unique (no duplicates)

### 4.3 Test Idempotency

```sql
-- Run transform again - should only process new records
-- Count before
SELECT COUNT(*) as before_count FROM `shift_data.state_estimates`;

-- Run transform.sql again

-- Count after (should be same or only include new records)
SELECT COUNT(*) as after_count FROM `shift_data.state_estimates`;
```

**Validation Checks:**
- [ ] Running transform twice doesn't create duplicates
- [ ] Only unprocessed records are inserted

---

## Step 5: Validate Real-World Scenarios

### 5.1 High Recovery Scenario

Look for records where:
- High HRV (> 50)
- Low resting HR (< 60)
- Good sleep (> 7 hours)

**Expected:** High recovery score (0.7-1.0)

### 5.2 High Stress Scenario

Look for records where:
- Low HRV (< 30)
- High resting HR (> 75)
- Poor sleep

**Expected:** High stress score (0.7-1.0)

### 5.3 High Fatigue Scenario

Look for records where:
- Poor sleep (< 5 hours)
- High workout intensity
- Low activity

**Expected:** High fatigue score (0.7-1.0)

---

## Step 6: Performance Check

```sql
-- Check query performance
SELECT
  COUNT(*) as total_input_records,
  COUNT(DISTINCT user_id) as unique_users,
  MIN(timestamp) as earliest_timestamp,
  MAX(timestamp) as latest_timestamp
FROM `shift_data.v_state_estimator_input_v1`;
```

**Validation Checks:**
- [ ] View queries complete in reasonable time (< 30 seconds for reasonable dataset size)
- [ ] No timeout errors

---

## Notes

- Run these checks after deploying to dev environment
- If any check fails, document the issue and fix SQL accordingly
- Re-run checks after SQL changes
- Consider creating test data if no real data exists yet

---

## Quick Test Command

To quickly test the pipeline locally (without Cloud Function):

```bash
cd pipeline/state_estimator
export GCP_PROJECT_ID=shift-dev-478422
uv run python -m src.main --project-id $GCP_PROJECT_ID
```

This will:
1. Create/update views
2. Run transform (insert into state_estimates)
3. Use existing repository pattern

Then validate in BigQuery console using the queries above.









