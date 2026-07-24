# =============================================================================
# BIGQUERY DATASETS
# One dataset per medallion stage (semantic names), so each stage can be shared
# independently as a Data Product later. No `raw` stage: the source is the
# external public GA4 dataset, referenced live via the ga4_events declaration.
#   processed  = cleansed/flattened events  (was: silver)
#   serving    = features, model, predictions, eval  (was: gold)
# =============================================================================

resource "google_bigquery_dataset" "stages" {
  for_each = {
    processed = "PROCESSED: cleansed & flattened GA4 events"
    serving   = "SERVING: churn features, BQML model, evaluation & risk scores"
  }

  dataset_id  = each.key
  location    = var.dataset_location
  description = each.value

  # Demo convenience: let `tofu destroy` remove these even though Dataform
  # populates them with tables/models (all data is reproducible on re-run).
  delete_contents_on_destroy = true

  labels = {
    project = "datacloud-churn-prediction"
    purpose = "showcase"
    demo    = "churn-prediction"
    stage   = each.key
  }

  depends_on = [google_project_service.apis["bigquery.googleapis.com"]]
}
