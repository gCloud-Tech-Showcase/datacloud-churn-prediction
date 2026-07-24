# =============================================================================
# REQUIRED VARIABLES
# =============================================================================

variable "project_id" {
  description = "The GCP project ID (created out-of-band as a one-time prerequisite)"
  type        = string
  default     = "datacloud-churn"
}

variable "github_token" {
  description = "GitHub personal access token (repo scope) for the git-linked Dataform repository"
  type        = string
  sensitive   = true
}

# =============================================================================
# OPTIONAL VARIABLES
# =============================================================================

variable "region" {
  description = "The GCP region for regional resources (Dataform, Vertex)"
  type        = string
  default     = "us-central1"
}

variable "dataset_location" {
  description = "BigQuery dataset location (multi-region)"
  type        = string
  default     = "US"
}

variable "dataset_id" {
  description = "BigQuery dataset ID for the propensity modeling use case"
  type        = string
  default     = "propensity_modeling"
}

variable "git_repo_url" {
  description = "GitHub repository URL the managed Dataform repo pulls from"
  type        = string
  default     = "https://github.com/gCloud-Tech-Showcase/datacloud-churn-prediction.git"
}
