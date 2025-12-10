#!/bin/bash -e

# Script to test the adaptive intervention selector loop
# This helps verify preference modeling is working

PROJECT="shift-dev-478422"
DATASET="shift_data"

echo "🧪 Testing Adaptive Intervention Selector Loop"
echo "=============================================="
echo ""

# Step 1: Check catalog is loaded
echo "1️⃣ Checking intervention catalog..."
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT COUNT(*) as catalog_count
FROM \`$PROJECT.$DATASET.intervention_catalog\`
WHERE enabled = TRUE
EOF

echo ""
echo "2️⃣ Checking recent interventions..."
echo "   (Run this after generating some interventions)"
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT 
  intervention_instance_id,
  user_id,
  intervention_key,
  surface,
  created_at,
  status
FROM \`$PROJECT.$DATASET.intervention_instances\`
ORDER BY created_at DESC
LIMIT 5
EOF

echo ""
echo "3️⃣ Checking interaction events..."
echo "   (Run this after interacting with interventions in the app)"
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT 
  event_type,
  COUNT(*) as count
FROM \`$PROJECT.$DATASET.app_interactions\`
GROUP BY event_type
ORDER BY count DESC
EOF

echo ""
echo "4️⃣ Checking surface preferences..."
echo "   (Run this after some interactions have been recorded)"
bq query --use_legacy_sql=false --project_id="$PROJECT" --format=prettyjson <<EOF
SELECT 
  user_id,
  surface,
  shown_count,
  tap_primary_count,
  dismiss_manual_count,
  engagement_rate,
  annoyance_rate,
  preference_score
FROM \`$PROJECT.$DATASET.surface_preferences\`
ORDER BY user_id, surface
EOF

echo ""
echo "✅ Test queries complete!"
echo ""
echo "📝 Next steps:"
echo "   1. Generate some interventions (trigger state estimates)"
echo "   2. Interact with them in the iOS app (tap some, dismiss some)"
echo "   3. Run this script again to see preferences being calculated"
echo "   4. Check Cloud Function logs for preference-based selection"

