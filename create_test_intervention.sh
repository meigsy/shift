#!/bin/bash -e

# Script to create a test intervention in BigQuery for testing iOS app

PROJECT="shift-dev-478422"
DATASET="shift_data"
USER_ID="mock-user-default"
INTERVENTION_KEY="stress_high_notification"

echo "🧪 Creating test intervention in BigQuery..."
echo "   Project: $PROJECT"
echo "   Dataset: $DATASET"
echo "   User ID: $USER_ID"
echo "   Intervention: $INTERVENTION_KEY"
echo ""

# Generate UUID for intervention_instance_id
INTERVENTION_ID=$(python3 -c "import uuid; print(uuid.uuid4())")

echo "📝 Inserting intervention instance with ID: $INTERVENTION_ID"
echo ""

bq query --use_legacy_sql=false --project_id="$PROJECT" <<EOF
INSERT INTO \`$PROJECT.$DATASET.intervention_instances\` (
  intervention_instance_id,
  user_id,
  metric,
  level,
  surface,
  intervention_key,
  created_at,
  scheduled_at,
  sent_at,
  status
)
VALUES (
  '$INTERVENTION_ID',
  '$USER_ID',
  'stress',
  'high',
  'notification',
  '$INTERVENTION_KEY',
  CURRENT_TIMESTAMP(),
  CURRENT_TIMESTAMP(),
  NULL,
  'created'
)
EOF

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Test intervention created successfully!"
  echo ""
  echo "📱 Next steps:"
  echo "   1. Wait up to 60 seconds for the next poll cycle"
  echo "   2. The intervention banner should appear"
  echo "   3. It will stay visible for 30 seconds"
  echo ""
else
  echo ""
  echo "❌ Failed to create test intervention"
  exit 1
fi

















