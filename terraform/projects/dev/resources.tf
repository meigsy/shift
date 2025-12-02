
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

# Cloud Function IAM is handled automatically by gcloud functions deploy

