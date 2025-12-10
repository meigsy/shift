#!/bin/bash -e

# Script to load initial intervention catalog data into BigQuery

PROJECT="shift-dev-478422"
DATASET="shift_data"

echo "📚 Loading intervention catalog data into BigQuery..."
echo "   Project: $PROJECT"
echo "   Dataset: $DATASET"
echo ""

bq query --use_legacy_sql=false --project_id="$PROJECT" <<EOF
INSERT INTO \`$PROJECT.$DATASET.intervention_catalog\` (
  intervention_key,
  metric,
  level,
  surface,
  title,
  body,
  nudge_type,
  persona,
  enabled
)
VALUES
  (
    'stress_high_notification',
    'stress',
    'high',
    'notification',
    'Take a Short Reset',
    'You seem overloaded. Take a 5-minute break.',
    NULL,
    NULL,
    TRUE
  ),
  (
    'stress_medium_notification',
    'stress',
    'medium',
    'notification',
    'Quick Check-in',
    'How are you doing? Consider a breathing break.',
    NULL,
    NULL,
    TRUE
  ),
  (
    'stress_low_notification',
    'stress',
    'low',
    'notification',
    'Nice Work',
    'You are keeping stress low today. Keep it up!',
    NULL,
    NULL,
    TRUE
  )
EOF

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Intervention catalog loaded successfully!"
  echo ""
  echo "📊 Verifying data..."
  bq query --use_legacy_sql=false --project_id="$PROJECT" <<EOF
SELECT 
  intervention_key,
  metric,
  level,
  surface,
  title,
  enabled
FROM \`$PROJECT.$DATASET.intervention_catalog\`
ORDER BY level, intervention_key
EOF
  echo ""
  echo "✅ Catalog is ready! The intervention selector can now use these interventions."
else
  echo ""
  echo "❌ Failed to load intervention catalog"
  exit 1
fi

