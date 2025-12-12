CREATE OR REPLACE TABLE `shift-dev-478422.shift_data.intervention_catalog` AS
WITH nudges AS (
  SELECT * FROM UNNEST([
    STRUCT(
      'test_001' AS intervention_key,
      'stress' AS metric,
      'high' AS level,
      'low' AS target_level,
      'mind' AS nudge_type,
      NULL AS persona,
      'notification_banner' AS surface,
      'Test Title' AS title,
      'You are carrying too much right now.' AS body,
      TRUE AS enabled
    )
  ])
)
SELECT
  intervention_key,
  metric,
  level,
  target_level,
  nudge_type,
  persona,
  surface,
  title,
  body,
  enabled
FROM nudges;