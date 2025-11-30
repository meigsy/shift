
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

# Pub/Sub Topic for Watch Events
resource "google_pubsub_topic" "watch_events" {
  name    = "watch_events"
  project = var.project_id
  
  depends_on = [google_project_service.pubsub]
}

# Grant Backend Service Account permissions
resource "google_project_iam_member" "backend_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_bigquery_dataset_iam_member" "backend_bq" {
  dataset_id = google_bigquery_dataset.shift_data.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_pubsub_topic_iam_member" "backend_pubsub" {
  topic  = google_pubsub_topic.watch_events.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.backend.email}"
}

