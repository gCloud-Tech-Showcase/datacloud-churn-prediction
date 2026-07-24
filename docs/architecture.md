# Churn Prediction Architecture

Data flow and pipeline structure for user retention modeling with BigQuery ML.

---

## Pipeline Overview

```mermaid
graph TB
    subgraph "Raw Source - external, live"
        GA4[Firebase GA4<br/>Public Dataset]
    end

    subgraph "BigQuery + Dataform"
        subgraph "processed dataset"
            FLAT[events_flattened<br/>Unnested GA4]
        end

        subgraph "serving dataset"
            FEAT[training_features<br/>7-day Windows]
            MODEL[user_retention_model<br/>BQML Logistic Reg]
            FI[user_retention_model_feature_importance<br/>ML.GLOBAL_EXPLAIN]
            SCORES[user_risk_scores<br/>ML.PREDICT]
        end
    end

    subgraph "Vertex AI"
        REGISTRY[Model Registry<br/>Versioning]
    end

    GA4 --> FLAT
    FLAT --> FEAT
    FEAT --> MODEL
    MODEL --> REGISTRY
    MODEL --> FI
    MODEL --> SCORES

    classDef raw fill:#cd7f32,stroke:#333,color:#fff
    classDef processed fill:#c0c0c0,stroke:#333,color:#000
    classDef serving fill:#ffd700,stroke:#333,color:#000
    classDef external fill:#4285f4,stroke:#333,color:#fff

    class GA4 raw
    class FLAT processed
    class FEAT,MODEL,FI,SCORES serving
    class REGISTRY external
```

---

## Data Flow

```mermaid
sequenceDiagram
    participant GA4 as Firebase GA4<br/>Public Dataset
    participant Processed as processed.events_flattened
    participant Serving as serving.training_features
    participant BQML as user_retention_model
    participant VA as Vertex AI

    GA4->>Processed: Unnest event_params<br/>Parse dates, flatten structure
    Note over Processed: View with UNNEST,<br/>type conversions

    Processed->>Serving: Rolling 7-day windows<br/>Feature engineering
    Note over Serving: CTE-based:<br/>date_spine x users

    Serving->>BQML: CREATE MODEL<br/>TRANSFORM + LOGISTIC_REG
    Note over BQML: Auto-scaling,<br/>categorical encoding

    BQML->>VA: Register to Model Registry<br/>model_registry='vertex_ai'
    Note over VA: Versioning,<br/>explainability enabled
```

---

## Key Components

| Stage | Table | Purpose |
|-------|-------|---------|
| Raw (external) | `events_*` | Raw GA4 events (external declaration, live public dataset) |
| processed | `events_flattened` | Unnested event parameters |
| serving | `training_features` | Rolling 7-day window features |
| serving | `user_retention_model` | Trained logistic regression |
| serving | `user_retention_model_feature_importance` | Feature weights via ML.GLOBAL_EXPLAIN |
| serving | `user_risk_scores` | Materialized predictions |

---

## Feature Engineering

Uses **rolling 7-day windows** instead of static "first 7 days":

```
User A, Week 1: Days 1-7   → Did they return Days 8-14?
User A, Week 2: Days 8-14  → Did they return Days 15-21?
User A, Week 3: Days 15-21 → Did they return Days 22-28?
```

This creates multiple training rows per user, capturing behavioral dynamics over time.

---

## Navigation

[Guide](01-features.md) | [Quick Reference](quick.md) | [Repo README](../README.md)
