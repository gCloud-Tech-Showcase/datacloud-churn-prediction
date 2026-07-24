# =============================================================================
# OUTPUTS
# =============================================================================

output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "processed_dataset_id" {
  description = "The processed-stage BigQuery dataset ID (flattened GA4 events)"
  value       = google_bigquery_dataset.stages["processed"].dataset_id
}

output "serving_dataset_id" {
  description = "The serving-stage BigQuery dataset ID (features, model, predictions)"
  value       = google_bigquery_dataset.stages["serving"].dataset_id
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
