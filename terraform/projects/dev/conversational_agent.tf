# Service account for conversational_agent pipeline
resource "google_service_account" "conversational_agent" {
  account_id   = "conversational-agent-sa"
  display_name = "SHIFT Conversational Agent Pipeline Service Account"
  project      = var.project_id
}

# Grant conversational_agent Service Account permissions
resource "google_project_iam_member" "conversational_agent_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.conversational_agent.email}"
}

# Grant conversational_agent Service Account access to Secret Manager
resource "google_secret_manager_secret_iam_member" "conversational_agent_anthropic_api_key" {
  secret_id = var.anthropic_api_key_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.conversational_agent.email}"
  
  depends_on = [google_project_service.secret_manager]
}

# Cloud Run service for conversational_agent pipeline
resource "google_cloud_run_service" "conversational_agent" {
  name     = "conversational-agent"
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = google_service_account.conversational_agent.email
      
      containers {
        image = var.conversational_agent_image
        
        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "IDENTITY_PLATFORM_PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "ANTHROPIC_API_KEY_SECRET_ID"
          value = var.anthropic_api_key_secret_id
        }
        
        ports {
          container_port = 8080
        }
        
        resources {
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.cloud_run
  ]
}

# Allow unauthenticated access to conversational_agent Cloud Run (auth handled in app)
resource "google_cloud_run_service_iam_member" "conversational_agent_public_access" {
  service  = google_cloud_run_service.conversational_agent.name
  location = google_cloud_run_service.conversational_agent.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

