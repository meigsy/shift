-- Calculates user preferences for each intervention surface based on interaction history
-- Only considers interactions from the last 30 days to allow preferences to evolve over time

WITH cte_interactions_with_surface AS (
  SELECT
    ai.user_id,
    -- Map iOS event types to canonical preference modeling event types
    -- iOS sends: "shown", "tapped", "dismissed"
    -- Canonical: "shown", "tap_primary", "dismiss_manual", "dismiss_timeout"
    CASE
      WHEN ai.event_type = 'tapped' THEN 'tap_primary'
      WHEN ai.event_type = 'dismissed' THEN 'dismiss_manual'  -- iOS doesn't distinguish manual vs timeout yet
      ELSE ai.event_type  -- "shown" and any future types pass through
    END AS event_type,
    ai.timestamp,
    ii.surface
  FROM `${var.project_id}.shift_data.app_interactions` ai
  INNER JOIN `${var.project_id}.shift_data.intervention_instances` ii
    ON ai.intervention_instance_id = ii.intervention_instance_id
  WHERE ai.timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND ai.intervention_instance_id IS NOT NULL
)
SELECT
  user_id,
  surface,
  COUNTIF(event_type = 'shown') AS shown_count,
  COUNTIF(event_type = 'dismiss_manual') AS dismiss_manual_count,
  COUNTIF(event_type = 'dismiss_timeout') AS dismiss_timeout_count,
  COUNTIF(event_type = 'tap_primary') AS tap_primary_count,
  SAFE_DIVIDE(COUNTIF(event_type = 'tap_primary'), COUNTIF(event_type = 'shown')) AS engagement_rate,
  SAFE_DIVIDE(COUNTIF(event_type = 'dismiss_manual'), COUNTIF(event_type = 'shown')) AS annoyance_rate,
  SAFE_DIVIDE(COUNTIF(event_type = 'dismiss_timeout'), COUNTIF(event_type = 'shown')) AS ignore_rate,
  SAFE_DIVIDE(COUNTIF(event_type = 'tap_primary'), COUNTIF(event_type = 'shown')) - 
    SAFE_DIVIDE(COUNTIF(event_type = 'dismiss_manual'), COUNTIF(event_type = 'shown')) AS preference_score,
  CURRENT_TIMESTAMP() AS updated_at
FROM cte_interactions_with_surface
GROUP BY user_id, surface
