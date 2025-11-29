output "cloud_run_url" {
  description = "URL of the Cloud Run backend service"
  value       = google_cloud_run_service.backend.status[0].url
}

output "identity_platform_project_id" {
  description = "Identity Platform project ID"
  value       = var.project_id
}

output "service_account_email" {
  description = "Email of the backend service account"
  value       = google_service_account.backend.email
}


