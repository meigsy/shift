#!/bin/bash
# Clear interventions for testing

PROJECT=$(gcloud config get-value project 2>/dev/null || echo "shift-dev-441420")
DATASET="shift_data"
USER_ID="${1:-mock-user-default}"

echo "Clearing interventions for user: $USER_ID in project: $PROJECT"

# Clear app_interactions first (foreign key dependency)
bq query --use_legacy_sql=false --project_id="$PROJECT" --quiet <<SQL
DELETE FROM \`$PROJECT.$DATASET.app_interactions\`
WHERE user_id = '$USER_ID'
SQL

# Clear intervention_instances
bq query --use_legacy_sql=false --project_id="$PROJECT" --quiet <<SQL
DELETE FROM \`$PROJECT.$DATASET.intervention_instances\`
WHERE user_id = '$USER_ID'
SQL

echo "✅ Cleared interventions and interactions for $USER_ID"
