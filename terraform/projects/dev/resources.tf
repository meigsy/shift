
# Enable Firestore (Datastore Mode is simpler for key-value, but Native is standard)
resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
  
  depends_on = [google_project_service.firestore]
}

# BigQuery Dataset
resource "google_bigquery_dataset" "shift_data" {
  dataset_id  = "shift_data"
  project     = var.project_id
  location    = var.region
  description = "Primary dataset for SHIFT health data"
  
  # Explicit access control - Terraform manages all access
  access {
    role          = "WRITER"
    user_by_email = google_service_account.watch_events.email
  }
  
  access {
    role          = "WRITER"
    user_by_email = google_service_account.state_estimator.email
  }
  
  access {
    role          = "WRITER"
    user_by_email = google_service_account.intervention_selector.email
  }
  
  # Grant project owners/editors access (standard)
  access {
    role   = "OWNER"
    special_group = "projectOwners"
  }
  
  depends_on = [google_project_service.bigquery]
}

# BigQuery Table for Watch Events
resource "google_bigquery_table" "watch_events" {
  dataset_id = google_bigquery_dataset.shift_data.dataset_id
  table_id   = "watch_events"
  project    = var.project_id
  
  # Schema defined inline for simplicity
  schema = <<EOF
[
  {
    "name": "user_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "fetched_at",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  },
  {
    "name": "trace_id",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "payload",
    "type": "JSON",
    "mode": "REQUIRED"
  },
  {
    "name": "ingested_at",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  }
]
EOF

  depends_on = [google_bigquery_dataset.shift_data]
}

# BigQuery Table for State Estimates
resource "google_bigquery_table" "state_estimates" {
  dataset_id = google_bigquery_dataset.shift_data.dataset_id
  table_id   = "state_estimates"
  project    = var.project_id

  schema = <<EOF
[
  {
    "name": "user_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  },
  {
    "name": "trace_id",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "recovery",
    "type": "FLOAT64",
    "mode": "NULLABLE"
  },
  {
    "name": "readiness",
    "type": "FLOAT64",
    "mode": "NULLABLE"
  },
  {
    "name": "stress",
    "type": "FLOAT64",
    "mode": "NULLABLE"
  },
  {
    "name": "fatigue",
    "type": "FLOAT64",
    "mode": "NULLABLE"
  }
]
EOF

  depends_on = [google_bigquery_dataset.shift_data]
}

# Pub/Sub Topic for Watch Events
resource "google_pubsub_topic" "watch_events" {
  name    = "watch_events"
  project = var.project_id
  
  depends_on = [google_project_service.pubsub]
}

# Grant watch_events Service Account permissions
resource "google_project_iam_member" "watch_events_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.watch_events.email}"
}

# BigQuery dataset access is managed via access blocks in google_bigquery_dataset resource
# This gives Terraform full control and avoids deleted service account issues

resource "google_pubsub_topic_iam_member" "watch_events_pubsub" {
  topic  = google_pubsub_topic.watch_events.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.watch_events.email}"
}

resource "google_project_iam_member" "state_estimator_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.state_estimator.email}"
}

# Pub/Sub Topic for State Estimates
resource "google_pubsub_topic" "state_estimates" {
  name    = "state_estimates"
  project = var.project_id
  
  depends_on = [google_project_service.pubsub]
}

# Grant state_estimator Service Account permission to publish to state_estimates topic
resource "google_pubsub_topic_iam_member" "state_estimator_pubsub" {
  topic  = google_pubsub_topic.state_estimates.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.state_estimator.email}"
}

# BigQuery Table for Intervention Instances
resource "google_bigquery_table" "intervention_instances" {
  dataset_id = google_bigquery_dataset.shift_data.dataset_id
  table_id   = "intervention_instances"
  project    = var.project_id

  schema = <<EOF
[
  {
    "name": "intervention_instance_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "user_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "trace_id",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "metric",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "level",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "surface",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "intervention_key",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "created_at",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  },
  {
    "name": "scheduled_at",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  },
  {
    "name": "sent_at",
    "type": "TIMESTAMP",
    "mode": "NULLABLE"
  },
  {
    "name": "status",
    "type": "STRING",
    "mode": "REQUIRED"
  }
]
EOF

  depends_on = [google_bigquery_dataset.shift_data]
}

# BigQuery Table for Devices
resource "google_bigquery_table" "devices" {
  dataset_id = google_bigquery_dataset.shift_data.dataset_id
  table_id   = "devices"
  project    = var.project_id

  schema = <<EOF
[
  {
    "name": "user_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "device_token",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "platform",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "updated_at",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  }
]
EOF

  depends_on = [google_bigquery_dataset.shift_data]
}

# BigQuery Table for App Interactions
resource "google_bigquery_table" "app_interactions" {
  dataset_id = google_bigquery_dataset.shift_data.dataset_id
  table_id   = "app_interactions"
  project    = var.project_id

  schema = <<EOF
[
  {
    "name": "interaction_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "trace_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "user_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "intervention_instance_id",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "event_type",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  }
]
EOF

  depends_on = [google_bigquery_dataset.shift_data]
}

# BigQuery View for Full Trace Chain
resource "google_bigquery_table" "trace_full_chain" {
  dataset_id = google_bigquery_dataset.shift_data.dataset_id
  table_id   = "trace_full_chain"
  project    = var.project_id

  view {
    query = <<-EOT
WITH cte_watch_events AS (
  SELECT
    trace_id,
    user_id,
    fetched_at AS event_timestamp,
    payload AS watch_event_payload,
    ingested_at AS watch_event_ingested_at,
    'watch_event' AS event_type
  FROM `${var.project_id}.shift_data.watch_events`
  WHERE trace_id IS NOT NULL
),
cte_state_estimates AS (
  SELECT
    trace_id,
    user_id,
    timestamp AS event_timestamp,
    recovery,
    readiness,
    stress,
    fatigue,
    'state_estimate' AS event_type
  FROM `${var.project_id}.shift_data.state_estimates`
  WHERE trace_id IS NOT NULL
),
cte_intervention_instances AS (
  SELECT
    trace_id,
    user_id,
    intervention_instance_id,
    created_at AS event_timestamp,
    metric,
    level,
    surface,
    intervention_key,
    status,
    'intervention_created' AS event_type
  FROM `${var.project_id}.shift_data.intervention_instances`
  WHERE trace_id IS NOT NULL
),
cte_app_interactions AS (
  SELECT
    trace_id,
    user_id,
    intervention_instance_id,
    timestamp AS event_timestamp,
    event_type,
    CONCAT('interaction_', event_type) AS event_type_label
  FROM `${var.project_id}.shift_data.app_interactions`
  WHERE trace_id IS NOT NULL
),
cte_all_events AS (
  SELECT trace_id, user_id, event_timestamp, event_type, watch_event_payload, watch_event_ingested_at, NULL AS recovery, NULL AS readiness, NULL AS stress, NULL AS fatigue, NULL AS intervention_instance_id, NULL AS metric, NULL AS level, NULL AS surface, NULL AS intervention_key, NULL AS status, NULL AS interaction_event_type FROM cte_watch_events
  UNION ALL
  SELECT trace_id, user_id, event_timestamp, event_type, NULL, NULL, recovery, readiness, stress, fatigue, NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM cte_state_estimates
  UNION ALL
  SELECT trace_id, user_id, event_timestamp, event_type, NULL, NULL, NULL, NULL, NULL, NULL, intervention_instance_id, metric, level, surface, intervention_key, status, NULL FROM cte_intervention_instances
  UNION ALL
  SELECT trace_id, user_id, event_timestamp, event_type_label, NULL, NULL, NULL, NULL, NULL, NULL, intervention_instance_id, NULL, NULL, NULL, NULL, NULL, event_type FROM cte_app_interactions
)
SELECT
  trace_id,
  user_id,
  event_timestamp,
  event_type,
  watch_event_payload,
  watch_event_ingested_at,
  recovery,
  readiness,
  stress,
  fatigue,
  intervention_instance_id,
  metric,
  level,
  surface,
  intervention_key,
  status,
  interaction_event_type
FROM cte_all_events
ORDER BY trace_id, event_timestamp
EOT
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.watch_events,
    google_bigquery_table.state_estimates,
    google_bigquery_table.intervention_instances,
    google_bigquery_table.app_interactions
  ]
}

# BigQuery Table for Intervention Catalog
resource "google_bigquery_table" "intervention_catalog" {
  dataset_id = google_bigquery_dataset.shift_data.dataset_id
  table_id   = "intervention_catalog"
  project    = var.project_id

  schema = <<EOF
[
  {
    "name": "intervention_key",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "metric",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "level",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "surface",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "title",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "body",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "nudge_type",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "persona",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "enabled",
    "type": "BOOL",
    "mode": "REQUIRED"
  }
]
EOF

  depends_on = [google_bigquery_dataset.shift_data]
}

# BigQuery View for Surface Preferences
resource "google_bigquery_table" "surface_preferences" {
  dataset_id = google_bigquery_dataset.shift_data.dataset_id
  table_id   = "surface_preferences"
  project    = var.project_id

  view {
    query = <<-EOT
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
EOT
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.app_interactions,
    google_bigquery_table.intervention_instances
  ]
}

# Grant intervention_selector Service Account permissions
resource "google_project_iam_member" "intervention_selector_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.intervention_selector.email}"
}

resource "google_pubsub_topic_iam_member" "intervention_selector_pubsub_subscriber" {
  topic  = google_pubsub_topic.state_estimates.name
  role   = "roles/pubsub.subscriber"
  member = "serviceAccount:${google_service_account.intervention_selector.email}"
}

# Cloud Function IAM is handled automatically by gcloud functions deploy

