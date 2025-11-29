# SHIFT Fitness OS

**An ELT-driven health behavior system: Apple Watch + Withings → pipelines → state → intervention selector → iOS delivery.**

---

## Vision

SHIFT is a **personal health operating system**:

- Ingest wearable + lifestyle data
- Maintain real-time understanding of user state (recovery, fatigue, readiness, stress)
- Select the right micro-intervention at the right moment
- Deliver through native iOS + conversational AI

**Core philosophy**: Better health comes from *small, perfectly-timed actions*, not dashboards.

**Flow**: Data → State → Intervention → Delivery → Learning → Refinement

---

## Architecture

### System Flow

```
WATCH → HealthKit → iPhone → Pub/Sub → State Estimator → State → Selector → Notification → User → Outcomes → Learning
```

### Layers

1. **Input** — Wearables, chat, app interactions
2. **State Estimation** — SQL pipelines infer recovery/readiness/stress/fatigue
3. **Recommendation** — Preferences + rules select the right intervention
4. **Delivery** — Push notifications (trigger) + app pull (full content)
5. **Learning** — Completions/dismissals update preferences

### Principles

- **KISS**, YAGNI
- SQL-first
- Everything is a pipeline
- Pipelines own outputs
- Pub/Sub as glue
- Serverless where possible
- iOS native for ingestion + experience
- Backend is the brain

---

## Repository Structure

```
shift/
├── README.md              # This file
├── ios_app/               # iOS app
│   ├── HealthKit ingestion
│   ├── Sign in with Apple
│   ├── Push notification handling
│   └── Interaction event reporting
├── backend/               # FastAPI backend service
│   ├── Authentication (Sign in with Apple)
│   ├── Health data ingestion
│   └── User management
├── pipelines/             # All backend processing
│   ├── watch_events/      # iOS → Pub/Sub → BigQuery
│   ├── withings_events/   # Withings API → BigQuery
│   ├── chat_events/       # Conversation → BigQuery
│   ├── app_interactions/  # Surface reactions → BigQuery
│   ├── state_estimator/   # → stress, recovery, fatigue, readiness
│   ├── interaction_preferences/  # → user preferences from behavior
│   ├── intervention_selector/    # → picks & delivers interventions
│   └── intervention_catalog/     # Google Sheet sync (reference data)
├── terraform/             # GCP infrastructure
│   ├── projects/dev/
│   └── projects/prod/
└── docs/                  # Decision docs, venture materials
```

---

## Implementation Approach

- **Source drives the schema** — HealthKit dictates watch_events shape, Withings API dictates withings_events shape, etc.
- **No shared contract files** — Cursor/Claude reads source code, writes matching pipelines
- **Everything is a pipeline** — Standalone modules with inputs, outputs, Pub/Sub triggers
- **FastAPI + Pydantic** — Cloud Run services with automatic validation
- **SQL-first state estimation** — BigQuery scheduled queries

---

## Pipelines

Each pipeline is a standalone module with:

- `main.sql` or `main.py`
- Input views
- Output tables
- Pub/Sub triggers
- Tests
- Terraform infra

### Input Pipelines

| Pipeline | Source | Output |
|----------|--------|--------|
| `watch_events` | iOS app (HealthKit) | BigQuery raw events |
| `withings_events` | Withings API | BigQuery raw events |
| `chat_events` | Conversational agent | BigQuery messages |
| `app_interactions` | iOS app (gestures, reactions) | BigQuery interactions |

### Processing Pipelines

| Pipeline | Input | Output |
|----------|-------|--------|
| `state_estimator` | All events | stress, recovery, fatigue, readiness scores |
| `interaction_preferences` | app_interactions, chat_events | User preference model |
| `intervention_selector` | State + preferences + catalog | Selected intervention(s) |

### Reference Data

| Pipeline | Source | Output |
|----------|--------|--------|
| `intervention_catalog` | Google Sheet (SME-edited) | BigQuery reference table |

---

## Event Flow

```
┌─────────────────┐
│  watch_events   │────▶┐
└─────────────────┘     │
                        │
┌─────────────────┐     │     ┌─────────────────┐     ┌──────────────────────┐
│ withings_events │────▶├────▶│ state_estimator │────▶│ intervention_selector│────▶ Push ────▶ iOS
└─────────────────┘     │     └─────────────────┘     └──────────────────────┘
                        │                                       ▲
┌─────────────────┐     │                                       │
│   chat_events   │────▶┘                                       │
└─────────────────┘────▶┐                                       │
                        │                                       │
┌─────────────────┐     │     ┌────────────────────────┐        │
│ app_interactions│────▶┘────▶│interaction_preferences │────────┘
└─────────────────┘           └────────────────────────┘
```

Target latency: **20–30 seconds** end-to-end.

---

## Delivery Model

1. `intervention_selector` picks intervention
2. Backend sends push notification via APNs
3. iOS wakes, fetches full intervention details
4. iOS renders the intervention
5. User interaction → `app_interactions` → learning

Push is the trigger; app pulls full payload.

---

## iOS App

### Purpose

- HealthKit ingestion (Apple Watch data)
- Authentication (Sign in with Apple via GCP Identity Platform)
- Push notification receiving
- Surface rendering (SwiftUI)
- Interaction event reporting

### Authentication Flow

1. User signs in with Apple (native iOS flow)
2. iOS sends Apple credentials to backend `/auth/apple`
3. Backend verifies with Apple and exchanges with Identity Platform
4. Backend returns Identity Platform ID token
5. iOS uses ID token for authenticated API requests
6. Health data sync includes authentication headers

### Devices

- iPhone (primary)
- Apple Watch (sensor)
- Withings Body Scan (body composition)

### Interaction Surfaces

- SwiftUI-coded screens
- Push notifications
- Deep-link modals
- Conversational agent

---

## Infrastructure

### GCP Projects

- `shift-dev` — Development
- `shift-prod` — Production

### Terraform Structure

```
terraform/
├── projects/
│   ├── dev/
│   └── prod/
└── modules/
    ├── bigquery_pipeline/
    ├── pubsub_pipeline/
    └── cloud_function/
```

Each pipeline has Terraform for:
- Tables and views
- Pub/Sub topics
- Cloud Functions / Cloud Run

### Identities

- `sylvester-admin@` — Org admin (rarely used)
- `sylvester@` — Daily engineering

### Protections

- Org lien on prod
- Budget alerts
- IAM via Terraform
