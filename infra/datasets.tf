# =============================================================================
# BIGQUERY DATASETS
# =============================================================================

resource "google_bigquery_dataset" "propensity_modeling" {
  dataset_id  = var.dataset_id
  location    = var.dataset_location
  description = "GOLD/SILVER churn-prediction datasets for BQML propensity modeling"

  labels = {
    project = "datacloud-churn-prediction"
    purpose = "showcase"
    demo    = "churn-prediction"
  }

  depends_on = [google_project_service.apis["bigquery.googleapis.com"]]
}

resource "google_bigquery_dataset" "ga4_source" {
  dataset_id  = "ga4_source"
  location    = var.dataset_location
  description = "Source views over the GA4/Firebase public dataset (Flood-It!)"

  labels = {
    project = "datacloud-churn-prediction"
    purpose = "showcase"
    demo    = "churn-prediction"
  }

  depends_on = [google_project_service.apis["bigquery.googleapis.com"]]
}
