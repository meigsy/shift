-- Table definition for `shift_data.intervention_catalog` using CTE + UNNEST
-- This is the canonical source of truth for intervention catalog data
-- Managed as Infrastructure as Code via Terraform

CREATE OR REPLACE TABLE `shift_data.intervention_catalog` AS
WITH nudges AS (
  SELECT * FROM UNNEST([
    STRUCT(
      'stress_high_mind_001' AS intervention_key,
      'stress' AS metric,
      'high' AS level,
      'low' AS target_level,
      'mind' AS nudge_type,
      'Active Balance' AS persona,
      'notification_banner' AS surface,
      'Stress / High / Mind' AS title,
      'You are carrying too much right now. Step away, close your eyes, and remind yourself: This moment will pass. Let your breath lead you back.' AS body,
      TRUE AS enabled
    ),
    STRUCT(
      'stress_high_mind_002' AS intervention_key,
      'stress' AS metric,
      'high' AS level,
      'low' AS target_level,
      'mind' AS nudge_type,
      NULL AS persona,
      'notification_banner' AS surface,
      'Stress / High / Mind' AS title,
      'Remember, not everything is urgent. Your wellness is, though. Step away, breathe, and let your mind reset before re-entering.' AS body,
      TRUE AS enabled
    ),
    STRUCT(
      'stress_high_body_003' AS intervention_key,
      'stress' AS metric,
      'high' AS level,
      'low' AS target_level,
      'body' AS nudge_type,
      NULL AS persona,
      'notification_banner' AS surface,
      'Stress / High / Body' AS title,
      'Find a quiet corner. Place your hand over your heart, take 5 deep belly breaths, and feel your body slow everything down.' AS body,
      TRUE AS enabled
    ),
  ])
)
SELECT * FROM nudges LIMIT 10;
