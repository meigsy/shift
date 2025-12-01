output "watch_events_url" {
  description = "URL of the watch_events Cloud Run service"
  value       = google_cloud_run_service.watch_events.status[0].url
}

output "state_estimator_url" {
  description = "URL of the state_estimator Cloud Run service"
  value       = google_cloud_run_service.state_estimator.status[0].url
}

output "identity_platform_project_id" {
  description = "Identity Platform project ID"
  value       = var.project_id
}

output "watch_events_service_account_email" {
  description = "Email of the watch_events service account"
  value       = google_service_account.watch_events.email
}

output "state_estimator_service_account_email" {
  description = "Email of the state_estimator service account"
  value       = google_service_account.state_estimator.email
}





