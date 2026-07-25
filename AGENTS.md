# datacloud-churn-prediction

Standalone demo: public GA4 event data → engineered features over rolling
7-day windows → a BQML logistic regression predicting user retention, with
materialized risk scores. Orchestrated by Dataform, provisioned with OpenTofu.
No data seeding needed — the source is a public BigQuery dataset read live.

## Standing it up

```bash
./infra/scripts/setup.sh   # APIs + versioned state bucket + tofu init
cd infra && tofu apply     # zero required variables
```

`tofu apply` enables APIs, creates datasets + the runner service account + IAM,
stands up the Dataform repo, then triggers one pipeline run and blocks until it
finishes (~2-4 min, including model training).

Deploying elsewhere: change `project_id`'s default in `infra/variables.tf` —
that single value drives the provider, the resources, and the state bucket
name. Don't hardcode it anywhere else.

## Data model

Datasets are named for the **medallion stage**; the domain
(`propensity_modeling`) is a Dataform tag, never a dataset or table prefix.
There's no `raw` stage — the source is an external public table referenced by
declaration, so nothing lands.

| Dataset | Object | What |
| --- | --- | --- |
| — | `ga4_events` | Declaration only, pointing at the public GA4 sample |
| `processed` | `events_flattened` | Cleansed, flattened GA4 events (view) |
| `serving` | `training_features` | 7-day-window features + `will_return` label |
| `serving` | `user_retention_model` | BQML logistic regression, registered in Vertex |
| `serving` | `model_evaluation` | ML.EVALUATE metrics per training run |
| `serving` | `user_risk_scores` | Materialized ML.PREDICT output + risk tiers |
| `serving` | `user_retention_model_feature_importance` | Explainability |
| `assertions` | `training_features_integrity`, `risk_score_validity` | Hard-fail; rows = failed run |
| `assertions` | `model_quality` | Warning view; empty = healthy |

`definitions/` mirrors this: `sources/`, `processed/`, `serving/`,
`assertions/`, `monitoring/`.

## Verifying

```sql
SELECT ROUND(roc_auc,4) roc_auc, ROUND(accuracy,2) accuracy
FROM `serving.model_evaluation`;          -- ~0.7535 / ~0.72

SELECT risk_category, COUNT(*) n, ROUND(AVG(actual_outcome),2) actual_return_rate
FROM `serving.user_risk_scores` GROUP BY 1;
-- should stratify monotonically: HIGH ~0.22 · MEDIUM ~0.41 · LOW ~0.81

SELECT * FROM `assertions.training_features_integrity`;  -- must be empty
SELECT * FROM `assertions.model_quality`;                -- empty = healthy
```

The risk tiers stratifying monotonically is the real proof the model works —
a flat rate across tiers means the predictions carry no signal even if ROC AUC
looks fine.

## Gotchas

- **GA4 dates are `YYYYMMDD` strings** — `PARSE_DATE('%Y%m%d', col)`, not a
  cast.
- **`${self()}` is required** inside the BQML `CREATE MODEL` definition; a
  plain name won't resolve.
- **`risk_category` is derived from the UNROUNDED probability**, while
  `return_probability` is stored `ROUND(...,4)`. A value like 0.29996 stores as
  0.3000 yet correctly bands HIGH — which is why the band assertion carves out
  rows within half a rounding step of a threshold.
- **Scheduled runs are ON here** (`enable_scheduled_runs`), so the model
  retrains hourly. Cheap for a logistic regression on ~18K rows, but it does
  run indefinitely — dial it back if that matters.
- **Model metrics move between runs** as the training window shifts. That's
  why quality checks live in `monitoring/` and never hard-fail.
- **Non-interactive shells don't load `.envrc`**, so pass `--project` to
  `bq`/`gcloud` explicitly rather than trusting the ambient project.

## Teardown

```bash
cd infra && tofu destroy
```

Removes the demo including dataset contents and the model. Deliberately **not**
removed, because Tofu didn't create them: the project and the state bucket
(`gs://datacloud-churn-tfstate`) — destroying the bucket holding the state
mid-destroy would be self-defeating.

## More

`README.md` for the human-facing walkthrough, `docs/` for architecture and
query guides. Repo-wide engineering standards are not kept here — they live in
the user-level agent toolkit.
