#!/bin/bash -e

# Script to test suppression logic in the adaptive selector
# Verifies that surfaces with high annoyance rates are suppressed

PROJECT="shift-dev-478422"
DATASET="shift_data"
USER_ID="mock-user-default"

echo "🧪 Testing Suppression Logic"
echo "============================"
echo ""

echo "1️⃣ Current surface preferences for user: $USER_ID"
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT 
  surface,
  shown_count,
  dismiss_manual_count,
  annoyance_rate,
  preference_score,
  CASE 
    WHEN shown_count >= 5 AND annoyance_rate > 0.7 THEN 'SUPPRESSED'
    ELSE 'ACTIVE'
  END as suppression_status
FROM \`$PROJECT.$DATASET.surface_preferences\`
WHERE user_id = '$USER_ID'
EOF

echo ""
echo "2️⃣ Available interventions in catalog:"
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT 
  intervention_key,
  metric,
  level,
  surface,
  enabled
FROM \`$PROJECT.$DATASET.intervention_catalog\`
WHERE metric = 'stress' AND enabled = TRUE
ORDER BY level
EOF

echo ""
echo "3️⃣ Expected behavior:"
echo "   - If surface 'notification' has annoyance_rate > 0.7 AND shown_count >= 5"
echo "   - All interventions with surface='notification' should be suppressed"
echo "   - Selector should return None (no intervention created)"
echo ""

echo "4️⃣ Simulating selector logic..."
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
WITH cte_catalog AS (
  SELECT 
    intervention_key,
    metric,
    level,
    surface,
    title,
    body
  FROM \`$PROJECT.$DATASET.intervention_catalog\`
  WHERE metric = 'stress' AND enabled = TRUE
),
cte_prefs AS (
  SELECT 
    surface,
    preference_score,
    annoyance_rate,
    shown_count,
    CASE 
      WHEN shown_count >= 5 AND annoyance_rate > 0.7 THEN -1.0
      ELSE preference_score
    END as final_score
  FROM \`$PROJECT.$DATASET.surface_preferences\`
  WHERE user_id = '$USER_ID'
)
SELECT 
  c.intervention_key,
  c.level,
  c.surface,
  COALESCE(p.final_score, 0.0) as final_score,
  COALESCE(p.annoyance_rate, 0.0) as annoyance_rate,
  COALESCE(p.shown_count, 0) as shown_count,
  CASE 
    WHEN COALESCE(p.final_score, 0.0) < 0 THEN 'SUPPRESSED'
    ELSE 'AVAILABLE'
  END as status
FROM cte_catalog c
LEFT JOIN cte_prefs p ON c.surface = p.surface
ORDER BY c.level, final_score DESC
EOF

echo ""
echo "✅ Suppression test complete!"
echo ""
echo "📊 Interpretation:"
echo "   - Status = 'SUPPRESSED': Intervention will NOT be selected"
echo "   - Status = 'AVAILABLE': Intervention CAN be selected"
echo "   - If all are SUPPRESSED, selector returns None"

