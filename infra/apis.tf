# =============================================================================
# ENABLED APIS
# Only the services the churn-prediction demo actually uses.
# =============================================================================

resource "google_project_service" "apis" {
  for_each = toset([
    "bigquery.googleapis.com",     # BQML training + queries
    "aiplatform.googleapis.com",   # Vertex AI Model Registry (BQML model_registry='vertex_ai')
    "dataform.googleapis.com",     # managed git-linked Dataform repository
    "secretmanager.googleapis.com" # stores the GitHub token for Dataform
  ])

  service            = each.value
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Project metadata (used by other resources)
# -----------------------------------------------------------------------------

data "google_project" "current" {}
