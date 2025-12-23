output "watch_events_url" {
  description = "URL of the watch_events Cloud Run service"
  value       = google_cloud_run_service.watch_events.status[0].url
}

output "state_estimator_function_name" {
  description = "Name of the state_estimator Cloud Function (deployed via gcloud)"
  value       = "state-estimator"
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

output "intervention_selector_service_account_email" {
  description = "Email of the intervention_selector service account"
  value       = google_service_account.intervention_selector.email
}

output "conversational_agent_url" {
  description = "URL of the conversational_agent Cloud Run service"
  value       = google_cloud_run_service.conversational_agent.status[0].url
}

output "conversational_agent_service_account_email" {
  description = "Email of the conversational_agent service account"
  value       = google_service_account.conversational_agent.email
}





