#!/bin/bash -e

# Clear test data for mock-user-default from all pipeline tables
# This allows clean end-to-end testing

PROJECT="shift-dev-478422"
DATASET="shift_data"
TEST_USER_ID="mock-user-default"

echo "🧹 Clearing test data for user: $TEST_USER_ID"
echo ""

# Delete from app_interactions first (has foreign key to intervention_instances)
echo "Deleting from app_interactions..."
bq query --use_legacy_sql=false --project_id=$PROJECT --format=prettyjson \
  "DELETE FROM \`$PROJECT.$DATASET.app_interactions\` WHERE user_id = '$TEST_USER_ID'" > /dev/null 2>&1 || echo "  (no data to delete)"

# Delete from intervention_instances
echo "Deleting from intervention_instances..."
bq query --use_legacy_sql=false --project_id=$PROJECT --format=prettyjson \
  "DELETE FROM \`$PROJECT.$DATASET.intervention_instances\` WHERE user_id = '$TEST_USER_ID'" > /dev/null 2>&1 || echo "  (no data to delete)"

# Delete from state_estimates
echo "Deleting from state_estimates..."
bq query --use_legacy_sql=false --project_id=$PROJECT --format=prettyjson \
  "DELETE FROM \`$PROJECT.$DATASET.state_estimates\` WHERE user_id = '$TEST_USER_ID'" > /dev/null 2>&1 || echo "  (no data to delete)"

# Delete from watch_events
echo "Deleting from watch_events..."
bq query --use_legacy_sql=false --project_id=$PROJECT --format=prettyjson \
  "DELETE FROM \`$PROJECT.$DATASET.watch_events\` WHERE user_id = '$TEST_USER_ID'" > /dev/null 2>&1 || echo "  (no data to delete)"

echo ""
echo "✅ Test data cleared for user: $TEST_USER_ID"
echo ""
echo "Note: surface_preferences view will automatically update (30-day window)"
echo "      trace_full_chain view will automatically update (derived from above tables)"
