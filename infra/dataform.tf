# =============================================================================
# DATAFORM
# Managed, git-linked repository + release/workflow schedule + IAM.
# The repository pulls compiled SQL from git_repo_url, so the GitHub repo must
# already contain this code on `main` before `tofu apply`.
# =============================================================================

# -----------------------------------------------------------------------------
# Dataform Service Identity
# -----------------------------------------------------------------------------

resource "google_project_service_identity" "dataform" {
  provider = google-beta
  project  = var.project_id
  service  = "dataform.googleapis.com"

  depends_on = [google_project_service.apis["dataform.googleapis.com"]]
}

# -----------------------------------------------------------------------------
# Secret Manager (GitHub token for Dataform)
# -----------------------------------------------------------------------------

resource "google_secret_manager_secret" "github_token" {
  secret_id = "dataform-github-token"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret_version" "github_token" {
  secret      = google_secret_manager_secret.github_token.id
  secret_data = var.github_token
}

resource "google_secret_manager_secret_iam_member" "dataform_access" {
  secret_id = google_secret_manager_secret.github_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_project_service_identity.dataform.email}"

  depends_on = [google_project_service_identity.dataform]
}

# -----------------------------------------------------------------------------
# Dataform execution service account
# Workflow invocations run AS this SA. Newly created projects enforce "strict
# act-as" IAM checks, which require the workflow_config to name an explicit
# execution SA (the Dataform service agent alone is not accepted). This SA holds
# the BigQuery + Vertex permissions the pipeline needs; the Dataform service
# agent is granted actAs on it so Dataform can impersonate it at run time.
# -----------------------------------------------------------------------------

resource "google_service_account" "dataform_runner" {
  account_id   = "dataform-runner"
  display_name = "Dataform workflow execution"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

resource "google_project_iam_member" "runner_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataform_runner.email}"
}

# dataViewer is not needed — dataEditor is a superset that includes read access.
resource "google_project_iam_member" "runner_bq_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dataform_runner.email}"
}

# Required so BQML CREATE MODEL can register the model in the Vertex AI Model Registry
# (model_registry='vertex_ai'). Registration fails after training without this.
resource "google_project_iam_member" "runner_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.dataform_runner.email}"
}

# Let the Dataform service agent impersonate the runner SA.
# - serviceAccountUser (actAs): required at config time to name the SA on the
#   workflow_config under strict act-as checks.
# - serviceAccountTokenCreator (getAccessToken): required at run time so Dataform
#   can mint tokens for the runner and execute the workflow as it.
resource "google_service_account_iam_member" "dataform_impersonate_runner" {
  for_each = toset([
    "roles/iam.serviceAccountUser",
    "roles/iam.serviceAccountTokenCreator",
  ])
  service_account_id = google_service_account.dataform_runner.name
  role               = each.value
  member             = "serviceAccount:${google_project_service_identity.dataform.email}"
}

# -----------------------------------------------------------------------------
# Dataform Repository
# -----------------------------------------------------------------------------

resource "google_dataform_repository" "main" {
  provider = google-beta
  name     = "datacloud-churn-prediction"
  region   = var.region

  git_remote_settings {
    url                                 = var.git_repo_url
    default_branch                      = "main"
    authentication_token_secret_version = google_secret_manager_secret_version.github_token.id
  }

  depends_on = [
    google_project_service.apis["dataform.googleapis.com"],
    google_secret_manager_secret_iam_member.dataform_access
  ]
}

# -----------------------------------------------------------------------------
# Dataform Release Configuration
# Compiles `main` hourly. default_database overrides workflow_settings.yaml's
# defaultProject server-side, so forkers get their own project without editing YAML.
# -----------------------------------------------------------------------------

resource "google_dataform_repository_release_config" "main" {
  provider   = google-beta
  project    = var.project_id
  region     = var.region
  repository = google_dataform_repository.main.name

  name          = "production"
  git_commitish = "main"

  cron_schedule = "0 * * * *"
  time_zone     = "America/Los_Angeles"

  code_compilation_config {
    default_database = var.project_id
    default_location = var.dataset_location
  }
}

# -----------------------------------------------------------------------------
# Dataform Workflow Configuration
# -----------------------------------------------------------------------------

resource "google_dataform_repository_workflow_config" "main" {
  provider       = google-beta
  project        = var.project_id
  region         = var.region
  repository     = google_dataform_repository.main.name
  release_config = google_dataform_repository_release_config.main.id

  name = "full-workflow"

  invocation_config {
    service_account                          = google_service_account.dataform_runner.email
    fully_refresh_incremental_tables_enabled = true
    transitive_dependencies_included         = true
    transitive_dependents_included           = false
  }

  depends_on = [google_service_account_iam_member.dataform_impersonate_runner]
}
