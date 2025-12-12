WITH cte_watch_events AS (
    SELECT
        user_id,
        fetched_at,
        ingested_at,
        trace_id,
        payload
    FROM `${project_id}.shift_data.watch_events`
),
cte_hrv_agg AS (
    SELECT
        user_id,
        fetched_at,
        AVG(CAST(JSON_EXTRACT_SCALAR(item, '$.value') AS FLOAT64)) AS avg_hrv_value
    FROM cte_watch_events,
    UNNEST(JSON_EXTRACT_ARRAY(payload, '$.hrv')) AS item
    GROUP BY user_id, fetched_at
),
cte_resting_hr_agg AS (
    SELECT
        user_id,
        fetched_at,
        AVG(CAST(JSON_EXTRACT_SCALAR(item, '$.value') AS FLOAT64)) AS avg_resting_hr_value
    FROM cte_watch_events,
    UNNEST(JSON_EXTRACT_ARRAY(payload, '$.restingHeartRate')) AS item
    GROUP BY user_id, fetched_at
),
cte_sleep_agg AS (
    SELECT
        user_id,
        fetched_at,
        COUNT(*) AS sleep_sample_count,
        SUM(TIMESTAMP_DIFF(
            CAST(JSON_EXTRACT_SCALAR(item, '$.endDate') AS TIMESTAMP),
            CAST(JSON_EXTRACT_SCALAR(item, '$.startDate') AS TIMESTAMP),
            MINUTE
        )) AS total_sleep_minutes
    FROM cte_watch_events,
    UNNEST(JSON_EXTRACT_ARRAY(payload, '$.sleep')) AS item
    WHERE JSON_EXTRACT_SCALAR(item, '$.stage') = 'DEEP'
    GROUP BY user_id, fetched_at
),
cte_workout_agg AS (
    SELECT
        user_id,
        fetched_at,
        SUM(CAST(JSON_EXTRACT_SCALAR(item, '$.totalEnergyBurned') AS FLOAT64)) AS total_workout_energy,
        SUM(CAST(JSON_EXTRACT_SCALAR(item, '$.duration') AS FLOAT64)) AS total_workout_duration
    FROM cte_watch_events,
    UNNEST(JSON_EXTRACT_ARRAY(payload, '$.workouts')) AS item
    GROUP BY user_id, fetched_at
),
cte_activity_agg AS (
    SELECT
        user_id,
        fetched_at,
        SUM(CAST(JSON_EXTRACT_SCALAR(item, '$.value') AS FLOAT64)) AS total_steps
    FROM cte_watch_events,
    UNNEST(JSON_EXTRACT_ARRAY(payload, '$.steps')) AS item
    GROUP BY user_id, fetched_at
)
SELECT
    e.user_id,
    e.fetched_at AS timestamp,
    e.ingested_at,
    e.trace_id,
    COALESCE(hrv.avg_hrv_value, 0.0) AS hrv_value,
    COALESCE(rhr.avg_resting_hr_value, 0.0) AS resting_hr_value,
    COALESCE(sleep.total_sleep_minutes, 0.0) AS sleep_minutes,
    COALESCE(sleep.sleep_sample_count, 0) AS sleep_sample_count,
    COALESCE(workout.total_workout_energy, 0.0) AS workout_energy,
    COALESCE(workout.total_workout_duration, 0.0) AS workout_duration,
    COALESCE(activity.total_steps, 0.0) AS steps_value,
    e.payload AS raw_payload
FROM cte_watch_events e
LEFT JOIN cte_hrv_agg hrv ON e.user_id = hrv.user_id AND e.fetched_at = hrv.fetched_at
LEFT JOIN cte_resting_hr_agg rhr ON e.user_id = rhr.user_id AND e.fetched_at = rhr.fetched_at
LEFT JOIN cte_sleep_agg sleep ON e.user_id = sleep.user_id AND e.fetched_at = sleep.fetched_at
LEFT JOIN cte_workout_agg workout ON e.user_id = workout.user_id AND e.fetched_at = workout.fetched_at
LEFT JOIN cte_activity_agg activity ON e.user_id = activity.user_id AND e.fetched_at = activity.fetched_at
