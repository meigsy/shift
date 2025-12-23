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
  default     = ""  # Optional - only needed for real Sign in with Apple
}

variable "apple_client_id" {
  description = "Apple Service ID (Client ID)"
  type        = string
  default     = ""  # Optional - only needed for real Sign in with Apple
}

variable "apple_key_id" {
  description = "Apple Key ID"
  type        = string
  sensitive   = true
  default     = ""  # Optional - only needed for real Sign in with Apple
}

variable "enable_identity_platform" {
  description = "Enable Identity Platform (required for real Apple auth)"
  type        = bool
  default     = false  # Set to true when you have Apple Developer account
}

variable "enable_apple_auth" {
  description = "Enable Apple Sign in with Apple OIDC provider"
  type        = bool
  default     = false  # Set to true when you have Apple Developer credentials
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
  default     = ""  # Optional for testing - can use mock auth endpoint
}

variable "watch_events_image" {
  description = "Container image for watch_events pipeline service"
  type        = string
  default     = "gcr.io/PROJECT_ID/watch-events:latest"
}

variable "conversational_agent_image" {
  description = "Container image for conversational_agent pipeline service"
  type        = string
  default     = "gcr.io/PROJECT_ID/conversational-agent:latest"
}

variable "anthropic_api_key_secret_id" {
  description = "Secret Manager secret ID for Anthropic API key"
  type        = string
  default     = "anthropic-api-key"
}



