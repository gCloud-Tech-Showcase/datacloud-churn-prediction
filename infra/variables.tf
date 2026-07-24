# =============================================================================
# REQUIRED VARIABLES
# =============================================================================

variable "project_id" {
  description = "The GCP project ID (created out-of-band as a one-time prerequisite)"
  type        = string
  default     = "datacloud-churn"
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
  description = "Trigger a Dataform run (compile main + workflow invocation as the runner SA) as the final step of apply and block until it finishes, so a fresh apply leaves the demo fully built. Runs once on first apply; set false to skip."
  type        = bool
  default     = true
}

variable "enable_scheduled_runs" {
  description = "Create the Dataform release + workflow configs that compile and run the pipeline hourly. Off by default so a clone-and-apply is a one-shot build (tables via run_pipeline_on_apply) with no recurring BQML retrain; set true for a self-refreshing deployment."
  type        = bool
  default     = false
}
