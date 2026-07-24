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

variable "git_repo_url" {
  description = "GitHub repository URL the managed Dataform repo pulls from"
  type        = string
  default     = "https://github.com/gCloud-Tech-Showcase/datacloud-churn-prediction.git"
}

variable "run_pipeline_on_apply" {
  description = "Trigger a Dataform run (compile main + workflow invocation as the runner SA) as the final step of apply and block until it finishes, so a fresh apply leaves the demo fully built. Runs once on first apply; set false to skip and rely on the hourly workflow cron / a manual trigger."
  type        = bool
  default     = true
}
