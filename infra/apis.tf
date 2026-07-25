# =============================================================================
# ENABLED APIS
# Only the services the churn-prediction demo actually uses.
# =============================================================================

resource "google_project_service" "apis" {
  for_each = toset([
    # Bootstrap pair — also pre-enabled imperatively by scripts/setup.sh, since the
    # provider needs CRM before it can manage any service. Declared here too so the
    # set is complete and self-documenting.
    "cloudresourcemanager.googleapis.com", # provider manages google_project_service via CRM
    "serviceusage.googleapis.com",         # enable/disable of the services below
    "bigquery.googleapis.com",             # BQML training + queries
    "aiplatform.googleapis.com",           # Vertex AI Model Registry (BQML model_registry='vertex_ai')
    "dataform.googleapis.com",             # managed git-linked Dataform repository (anonymous, public repo)
    "iam.googleapis.com",                  # execution service account
    "iamcredentials.googleapis.com",       # service-account impersonation (Dataform act-as runner)
    "datalineage.googleapis.com"           # automatic BigQuery/Dataform data lineage capture
  ])

  service            = each.value
  disable_on_destroy = false
}
