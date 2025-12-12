WITH cte_input AS (
    SELECT
        user_id,
        timestamp,
        trace_id,
        hrv_value,
        resting_hr_value,
        sleep_minutes,
        sleep_sample_count,
        workout_energy,
        workout_duration,
        steps_value,
        raw_payload
    FROM `${project_id}.shift_data.v_state_estimator_input_v1`
    --*************************************************************************************
    -- NOTE: Add limit here if needed for testing/batching
    --*************************************************************************************
)
SELECT
    input.user_id,
    input.timestamp,
    input.trace_id,
    input.hrv_value,
    input.resting_hr_value,
    input.sleep_minutes,
    input.sleep_sample_count,
    input.workout_energy,
    input.workout_duration,
    input.steps_value,
    input.raw_payload
FROM cte_input input
LEFT JOIN `${project_id}.shift_data.state_estimates` output
    ON input.user_id = output.user_id
    AND input.timestamp = output.timestamp
WHERE output.user_id IS NULL
ORDER BY input.timestamp
