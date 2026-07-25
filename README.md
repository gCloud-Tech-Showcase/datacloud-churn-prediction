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

That's it — **no GitHub token.** The managed Dataform repository pulls this code
over an *anonymous* git link, which works because the repo is **public**. The
only requirement is that the code lives on GitHub `main` before you apply (true
already if you cloned it).

## Quickstart

```bash
./infra/scripts/setup.sh   # one-time per project: APIs + state bucket + tofu init
cd infra && tofu apply     # zero required variables — every one has a default
```

`setup.sh` prepares everything Terraform can't bootstrap itself: it enables the
Cloud Resource Manager / Service Usage APIs (the provider needs them before it can
manage any service), creates a **versioned** state bucket `gs://<project>-tfstate`,
and runs `tofu init` pointed at it. Re-running is a safe no-op.

To deploy somewhere else, change `project_id`'s default in `infra/variables.tf` —
that single value drives the provider, the resources, and the state bucket name — or
pass `./infra/scripts/setup.sh --project=<id>`. No `terraform.tfvars` needed.

> **State lives remotely** in `gs://<project>-tfstate/tf/infra/`, versioned so a bad
> apply is recoverable. Each fork gets its own bucket in its own project, so there's
> nothing shared to collide with. Already have local state? `setup.sh --migrate`
> moves it up without touching any live resource.

`tofu apply` enables the required APIs, creates the two BigQuery datasets
(`processed`, `serving`), grants the Dataform service agent its IAM, and stands
up the git-linked Dataform repository. As its **final step it triggers the
pipeline once and blocks until it finishes** (~2–4 min), so a fresh apply leaves
the demo fully built — model trained, tables materialized.

> Needs `curl` + `python3` on the machine running apply (both come with `gcloud`).
> Set `run_pipeline_on_apply = false` to skip the auto-run.

> **Scheduled runs are off by default.** A clone-and-apply is a one-shot build.
> Set `enable_scheduled_runs = true` to also create the hourly release + workflow
> configs that recompile and retrain `main` on a cron (a self-refreshing deployment).

> **Ordering matters (git-linked Dataform):** the Dataform repository compiles from
> `git_repo_url`, so the GitHub repo must exist and hold this code on `main` before
> `tofu apply`. If you renamed the repo or forked it elsewhere, set `git_repo_url`
> in `terraform.tfvars`. A **private** fork can't use the anonymous link — you'd add
> a token back (`google_dataform_repository` + Secret Manager).

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
| Dataform repository | Git-linked to `main` over an anonymous (tokenless) link; created via the Dataform REST API |
| Dataform release + workflow configs | Only with `enable_scheduled_runs = true`; hourly compile + run of `main` |
| Dataform runner service account | `dataform-runner`; workflow invocations execute as it |
| First-run trigger | `run_pipeline_on_apply` (default on) runs the pipeline at end of apply |
| Enabled APIs | bigquery, aiplatform, dataform, iam, iamcredentials |

## Cleanup

```bash
cd infra && tofu destroy
```

This removes the demo resources, including the BigQuery datasets and their contents
(`delete_contents_on_destroy` — everything is reproducible on the next run).

Two things Tofu deliberately does **not** delete, because it didn't create them:
the **project** and the **state bucket** (`gs://datacloud-churn-tfstate`). Destroying
the bucket that holds the state mid-destroy would be self-defeating. Remove them
manually if you want the project gone:

```bash
gcloud storage rm -r gs://datacloud-churn-tfstate
gcloud projects delete datacloud-churn
```
