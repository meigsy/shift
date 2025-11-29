variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "apple_team_id" {
  description = "Apple Developer Team ID"
  type        = string
  sensitive   = true
}

variable "apple_client_id" {
  description = "Apple Service ID (Client ID)"
  type        = string
}

variable "apple_key_id" {
  description = "Apple Key ID"
  type        = string
  sensitive   = true
}

variable "apple_client_secret" {
  description = "Apple Client Secret (for OIDC provider config)"
  type        = string
  sensitive   = true
  default     = "" # Will be set manually or via secret manager
}

variable "apple_private_key_secret_id" {
  description = "Secret Manager secret ID for Apple private key"
  type        = string
  default     = "apple-private-key"
}

variable "identity_platform_api_key" {
  description = "API key for Identity Platform REST API"
  type        = string
  sensitive   = true
}

variable "backend_image" {
  description = "Container image for backend service"
  type        = string
  default     = "gcr.io/PROJECT_ID/shift-backend:latest"
}


