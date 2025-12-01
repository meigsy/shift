-- Transform: Calculate state estimates from unprocessed inputs
-- This reads from the unprocessed view and inserts results into state_estimates table

INSERT INTO shift_data.state_estimates (
    user_id,
    timestamp,
    recovery,
    readiness,
    stress,
    fatigue
)
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
    FROM shift_data.v_state_estimator_unprocessed_v1
),
cte_normalized_metrics AS (
    SELECT
        user_id,
        timestamp,
        -- Normalize HRV (typical range 20-60ms, higher is better for recovery)
        -- Scale to 0-1: (hrv - 20) / (60 - 20)
        LEAST(1.0, GREATEST(0.0, (hrv_value - 20.0) / 40.0)) AS normalized_hrv,
        -- Normalize resting HR (typical range 50-80 bpm, lower is better for recovery)
        -- Scale to 0-1: (80 - resting_hr) / (80 - 50)
        LEAST(1.0, GREATEST(0.0, (80.0 - resting_hr_value) / 30.0)) AS normalized_resting_hr,
        -- Normalize sleep (8 hours = 480 minutes is optimal)
        -- Scale to 0-1: sleep_minutes / 480, capped at 1.0
        LEAST(1.0, sleep_minutes / 480.0) AS normalized_sleep,
        -- Normalize workout intensity (higher energy = more stress/fatigue)
        -- Scale to 0-1: workout_energy / 1000 (1000 kcal is high intensity)
        LEAST(1.0, workout_energy / 1000.0) AS normalized_workout_intensity,
        -- Normalize steps (10k steps = 1.0)
        LEAST(1.0, steps_value / 10000.0) AS normalized_activity
    FROM cte_unprocessed
),
cte_state_scores AS (
    SELECT
        user_id,
        timestamp,
        -- Recovery: combination of HRV, resting HR, and sleep
        -- Higher HRV, lower resting HR, more sleep = higher recovery
        (
            (normalized_hrv * 0.4) +
            (normalized_resting_hr * 0.3) +
            (normalized_sleep * 0.3)
        ) AS recovery,
        -- Readiness: recovery adjusted by recent activity
        -- High recovery + moderate activity = high readiness
        (
            (
                (normalized_hrv * 0.4) +
                (normalized_resting_hr * 0.3) +
                (normalized_sleep * 0.3)
            ) * 0.7 +
            (normalized_activity * 0.3)
        ) AS readiness,
        -- Stress: inverse of HRV (lower HRV = higher stress)
        -- Also consider elevated resting HR
        (
            ((1.0 - normalized_hrv) * 0.6) +
            ((1.0 - normalized_resting_hr) * 0.4)
        ) AS stress,
        -- Fatigue: poor sleep + high workout intensity + low activity recovery
        -- High workout + low sleep = high fatigue
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
    fatigue
FROM cte_state_scores

