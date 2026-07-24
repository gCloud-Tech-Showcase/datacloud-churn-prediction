# =============================================================================
# DATAFORM
# Managed, git-linked repository + optional release/workflow schedule + IAM.
# The repository pulls compiled SQL from git_repo_url ANONYMOUSLY — no PAT /
# Secret Manager — which works because the GitHub repo is PUBLIC. The repo must
# already contain this code on `main` before `tofu apply`.
#
# The repository itself is created via the Dataform REST API (a terraform_data
# provisioner), not the google_dataform_repository resource: the provider
# enforces ExactlyOneOf(token / ssh / developer-connect) on git_remote_settings
# and so cannot express a tokenless (anonymous) git link, even though the REST
# API accepts one. Everything else (release/workflow configs, IAM) stays
# declarative and references the repository by name.
# (A private fork would need auth added back: recreate this as a
# google_dataform_repository with an authentication_token_secret_version
# pointing at a Secret Manager secret.)
# =============================================================================

locals {
  dataform_repository_name = "datacloud-churn-prediction"
}

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
# Dataform Repository (created via REST — anonymous public git link)
# create : idempotent GET-then-POST with a tokenless git_remote_settings.
# destroy: DELETE ?force=true so `tofu destroy` cleans it up.
# All values the destroy provisioner needs live in `input` (destroy-time
# provisioners may only reference `self`), and any change recreates the repo.
# -----------------------------------------------------------------------------

resource "terraform_data" "repository" {
  triggers_replace = {
    name   = local.dataform_repository_name
    region = var.region
    url    = var.git_repo_url
  }

  input = {
    project = var.project_id
    region  = var.region
    name    = local.dataform_repository_name
    url     = var.git_repo_url
    script  = "${path.module}/scripts/manage_repository.sh"
  }

  depends_on = [
    google_project_service_identity.dataform,
    google_project_service.apis["dataform.googleapis.com"],
  ]

  provisioner "local-exec" {
    command = "bash ${self.input.script} create"
    environment = {
      PROJECT = self.input.project
      REGION  = self.input.region
      REPO    = self.input.name
      URL     = self.input.url
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash ${self.input.script} delete"
    environment = {
      PROJECT = self.input.project
      REGION  = self.input.region
      REPO    = self.input.name
    }
  }
}

# -----------------------------------------------------------------------------
# Dataform Release Configuration (optional — enable_scheduled_runs)
# Compiles `main` hourly. default_database overrides workflow_settings.yaml's
# defaultProject server-side, so forkers get their own project without editing YAML.
# -----------------------------------------------------------------------------

resource "google_dataform_repository_release_config" "main" {
  count = var.enable_scheduled_runs ? 1 : 0

  provider   = google-beta
  project    = var.project_id
  region     = var.region
  repository = local.dataform_repository_name

  name          = "production"
  git_commitish = "main"

  cron_schedule = "0 * * * *"
  time_zone     = "America/Los_Angeles"

  code_compilation_config {
    default_database = var.project_id
    default_location = var.dataset_location
  }

  depends_on = [terraform_data.repository]
}

# -----------------------------------------------------------------------------
# Dataform Workflow Configuration (optional — enable_scheduled_runs)
# -----------------------------------------------------------------------------

resource "google_dataform_repository_workflow_config" "main" {
  count = var.enable_scheduled_runs ? 1 : 0

  provider       = google-beta
  project        = var.project_id
  region         = var.region
  repository     = local.dataform_repository_name
  release_config = google_dataform_repository_release_config.main[0].id

  name = "full-workflow"

  # Execute hourly, 15 min after the release config compiles main (a release
  # config only produces compilation results — this is what actually runs the
  # DAG). Dial back or remove to stop the pipeline self-refreshing.
  cron_schedule = "15 * * * *"
  time_zone     = "America/Los_Angeles"

  invocation_config {
    service_account                          = google_service_account.dataform_runner.email
    fully_refresh_incremental_tables_enabled = true
    transitive_dependencies_included         = true
    transitive_dependents_included           = false
  }

  depends_on = [google_service_account_iam_member.dataform_impersonate_runner]
}

# -----------------------------------------------------------------------------
# First-run trigger (optional)
# There is no declarative Terraform resource for a Dataform workflow invocation,
# so kick the first run off imperatively at the end of apply and block until it
# finishes — a fresh apply then leaves the demo fully built instead of waiting
# up to an hour for the workflow cron. Runs once (on create); subsequent applies
# are no-ops. Disable with run_pipeline_on_apply = false.
# -----------------------------------------------------------------------------

resource "terraform_data" "run_pipeline" {
  count = var.run_pipeline_on_apply ? 1 : 0

  # The auto-run creates its own compilation result + workflow invocation via
  # REST, so it's independent of the (optional) scheduled configs. It needs the
  # repository to compile from, the runner's BigQuery/Vertex grants, and the
  # service agent's impersonation rights over the runner.
  depends_on = [
    terraform_data.repository,
    google_service_account_iam_member.dataform_impersonate_runner,
    google_project_iam_member.runner_bq_job_user,
    google_project_iam_member.runner_bq_data_editor,
    google_project_iam_member.runner_vertex_ai_user,
  ]

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/run_pipeline.sh"
    environment = {
      PROJECT   = var.project_id
      REGION    = var.region
      REPO      = local.dataform_repository_name
      RUNNER_SA = google_service_account.dataform_runner.email
    }
  }
}
