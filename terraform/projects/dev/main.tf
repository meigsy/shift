terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "identity_toolkit" {
  service = "identitytoolkit.googleapis.com"
  project = var.project_id
  
  disable_on_destroy = false
}

resource "google_project_service" "cloud_run" {
  service = "run.googleapis.com"
  project = var.project_id
  
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  service = "iam.googleapis.com"
  project = var.project_id
  
  disable_on_destroy = false
}

resource "google_project_service" "secret_manager" {
  service = "secretmanager.googleapis.com"
  project = var.project_id
  
  disable_on_destroy = false
}

resource "google_project_service" "firestore" {
  service = "firestore.googleapis.com"
  project = var.project_id
  
  disable_on_destroy = false
}

resource "google_project_service" "bigquery" {
  service = "bigquery.googleapis.com"
  project = var.project_id
  
  disable_on_destroy = false
}

resource "google_project_service" "pubsub" {
  service = "pubsub.googleapis.com"
  project = var.project_id
  
  disable_on_destroy = false
}

# Enable Identity Platform (optional - only needed for real Apple auth)
resource "google_identity_platform_config" "default" {
  count   = var.enable_identity_platform ? 1 : 0
  project = var.project_id
  
  depends_on = [google_project_service.identity_toolkit]
}

# Configure Apple as OIDC provider (conditional - only if enabled)
resource "google_identity_platform_oauth_idp_config" "apple" {
  count         = var.enable_identity_platform && var.enable_apple_auth ? 1 : 0
  project       = var.project_id
  name          = "apple"
  display_name  = "Apple"
  enabled       = true
  client_id     = var.apple_client_id
  client_secret = var.apple_client_secret
  issuer        = "https://appleid.apple.com"
  
  depends_on = [google_identity_platform_config.default]
}

# Service account for Cloud Run backend
resource "google_service_account" "backend" {
  account_id   = "shift-backend-sa"
  display_name = "SHIFT Backend Service Account"
  project      = var.project_id
}

# Grant service account access to Secret Manager (only if Apple auth enabled)
resource "google_secret_manager_secret_iam_member" "apple_private_key" {
  count     = var.enable_apple_auth ? 1 : 0
  secret_id = var.apple_private_key_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
  
  depends_on = [google_project_service.secret_manager]
}

# Cloud Run service for backend
resource "google_cloud_run_service" "backend" {
  name     = "shift-backend"
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = google_service_account.backend.email
      
      containers {
        image = var.backend_image
        
        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "IDENTITY_PLATFORM_PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "IDENTITY_PLATFORM_API_KEY"
          value = var.identity_platform_api_key != "" ? var.identity_platform_api_key : "dummy"
        }
        
        env {
          name  = "APPLE_CLIENT_ID"
          value = var.apple_client_id != "" ? var.apple_client_id : "com.shift.ios-app"
        }
        
        env {
          name  = "APPLE_KEY_ID"
          value = var.apple_key_id != "" ? var.apple_key_id : ""
        }
        
        env {
          name  = "APPLE_TEAM_ID"
          value = var.apple_team_id != "" ? var.apple_team_id : ""
        }
        
        env {
          name = "APPLE_PRIVATE_KEY_SECRET_ID"
          value = var.apple_private_key_secret_id
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

# Allow unauthenticated access to Cloud Run (auth handled in app)
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_service.backend.name
  location = google_cloud_run_service.backend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}


