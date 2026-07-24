# =============================================================================
# OUTPUTS
# =============================================================================

output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "propensity_modeling_dataset_id" {
  description = "The propensity modeling BigQuery dataset ID"
  value       = google_bigquery_dataset.propensity_modeling.dataset_id
}

output "ga4_source_dataset_id" {
  description = "The GA4 source BigQuery dataset ID"
  value       = google_bigquery_dataset.ga4_source.dataset_id
}

output "dataform_repository_name" {
  description = "The Dataform repository name"
  value       = google_dataform_repository.main.name
}

output "dataform_release_config_name" {
  description = "The Dataform release configuration name"
  value       = google_dataform_repository_release_config.main.name
}

output "dataform_workflow_config_name" {
  description = "The Dataform workflow configuration name"
  value       = google_dataform_repository_workflow_config.main.name
}
