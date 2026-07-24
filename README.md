# Data Cloud — Churn Prediction

Predict which app users will churn, using **BigQuery ML** on a public GA4 dataset —
no Python, no data movement. Feature engineering, model training, evaluation, and
scoring all run as SQL, orchestrated by **Dataform**, with the trained model
registered in the **Vertex AI Model Registry**.

A standalone extract of the churn-prediction demo from the Data Cloud showcase.
Fork it, point it at your own GCP project, and `tofu apply`.

- **~79% ROC AUC** logistic-regression model
- **~18K training rows** engineered from **5.7M** raw GA4 events
- Rolling 7-day feature windows; everything reproducible from public data

See [`docs/`](docs/README.md) for the walkthrough and [`docs/quick.md`](docs/quick.md)
for copy-paste verification queries.

## Architecture

```
Firebase GA4 (public)          BigQuery + Dataform                    Vertex AI
  events_*  ──►  events_flattened ──► training_features ──► user_retention_model ──► Model Registry
                                                                              │
                                                    ┌─────────────────────────┼─────────────────────────┐
                                                    ▼                         ▼                         ▼
                                        model_evaluation   ..._feature_importance     user_risk_scores
```

Details: [`docs/architecture.md`](docs/architecture.md).

## Prerequisites

1. **A GCP project with billing linked.** This code does **not** create the project
   (destroying the stack should never risk deleting a project). Create it once:
   ```bash
   gcloud projects create datacloud-churn --organization=<YOUR_ORG_ID>
   gcloud billing projects link datacloud-churn --billing-account=<YOUR_BILLING_ACCOUNT>
   gcloud auth application-default login
   ```
2. **[OpenTofu](https://opentofu.org) ≥ 1.6** (`tofu`). Terraform ≥ 1.6 also works — the
   config is standard HCL.
3. **A GitHub personal access token** with `repo` scope. The managed Dataform
   repository pulls this code from GitHub, so the token is stored in Secret Manager
   and the repo must be pushed to GitHub **before** you apply (see below).

## Quickstart

```bash
# 1. Push this code to GitHub FIRST — the managed Dataform repo pulls from it.
#    (Skip if you cloned it and it already lives at the git_repo_url default.)
git remote -v   # confirm origin points at your GitHub repo on `main`

# 2. Provision.
cd infra
cp terraform.tfvars.example terraform.tfvars   # set github_token (+ any overrides)
tofu init
tofu apply
```

`tofu apply` enables the required APIs, creates the two BigQuery datasets
(`processed`, `serving`), grants the Dataform service agent its IAM,
and stands up the git-linked Dataform repository with an hourly release + workflow
schedule. As its **final step it triggers the pipeline once and blocks until it
finishes** (~2–4 min), so a fresh apply leaves the demo fully built — model
trained, tables materialized — instead of waiting for the first hourly cron.

> Needs `curl` + `python3` on the machine running apply (both come with `gcloud`).
> Set `run_pipeline_on_apply = false` to skip the auto-run and rely on the hourly
> workflow cron (or a manual trigger from the Dataform console) instead.

> **Ordering matters (git-linked Dataform):** the Dataform repository compiles from
> `git_repo_url`, so the GitHub repo must exist and hold this code on `main` before
> `tofu apply`. If you renamed the repo or forked it elsewhere, set `git_repo_url`
> in `terraform.tfvars`.

## Verify

After the pipeline runs, from the BigQuery console (or
`bq --project_id=datacloud-churn query`):

```sql
SELECT * FROM ML.EVALUATE(MODEL `serving.user_retention_model`);
```

Expect **ROC AUC ≈ 0.79** (0.74–0.84 is normal — the split is randomized), accuracy
≈ 0.74, top feature `days_active`. The full 7-query checklist with expected output is
in [`docs/quick.md`](docs/quick.md).

## What gets created

| Resource | Notes |
|----------|-------|
| BigQuery dataset `processed` | Cleansed/flattened GA4 events (view over the public Firebase dataset) |
| BigQuery dataset `serving` | Churn features, BQML model, evaluation & risk scores |
| Dataform repository + release/workflow | Git-linked, hourly compile + run of `main` |
| Dataform runner service account | `dataform-runner`; workflow invocations execute as it |
| Secret Manager `dataform-github-token` | Holds the GitHub PAT for Dataform |
| First-run trigger | `run_pipeline_on_apply` (default on) runs the pipeline at end of apply |
| Enabled APIs | bigquery, aiplatform, dataform, secretmanager, iam, iamcredentials |

## Cleanup

```bash
cd infra && tofu destroy
```

This removes the demo resources. The **project itself is left intact** (Tofu didn't
create it) — delete it separately with `gcloud projects delete datacloud-churn` if you
want it gone.
