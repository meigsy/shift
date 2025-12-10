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
├── pipeline/              # All pipeline services (Cloud Run)
│   ├── watch_events/      # FastAPI: Authentication + Health data ingestion
│   │   ├── Authentication (Sign in with Apple)
│   │   ├── Health data ingestion
│   │   └── User management
│   ├── state_estimator/   # State estimation pipeline
│   │   └── → stress, recovery, fatigue, readiness
│   ├── withings_events/   # Withings API → BigQuery (future)
│   ├── chat_events/       # Conversation → BigQuery (future)
│   ├── intervention_selector/    # ✅ Adaptive selector with preference modeling
│   └── [app_interactions written directly by iOS app to BigQuery]
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

| Pipeline | Input | Output | Status |
|----------|-------|--------|--------|
| `state_estimator` | All events | stress, recovery, fatigue, readiness scores | ✅ Complete |
| `intervention_selector` | State + preferences + catalog | Selected intervention(s) with adaptive learning | ✅ Complete |

**Adaptive Features**:
- Preference-based scoring (learns from user interactions)
- Suppression logic (high annoyance surfaces automatically suppressed)
- Rate limiting (3 interventions per 30 minutes per user)
- Data-driven catalog (BigQuery `intervention_catalog` table)

### Reference Data

| Resource | Source | Output | Status |
|----------|--------|--------|--------|
| `intervention_catalog` | BigQuery table (manually loaded) | BigQuery reference table | ✅ Complete |
| `surface_preferences` | BigQuery view (aggregates `app_interactions`) | User preference scores per surface | ✅ Complete |

---

## Event Flow

```
┌─────────────────┐
│  watch_events   │────▶┐
│  (✅ Complete)  │     │
└─────────────────┘     │
                        │
┌─────────────────┐     │     ┌─────────────────┐     ┌──────────────────────┐
│ withings_events │────▶├────▶│ state_estimator │────▶│ intervention_selector│────▶ iOS App
│  (Future)       │     │     │  (✅ Complete)  │     │  (✅ Complete)       │     (Polling)
└─────────────────┘     │     └─────────────────┘     └──────────────────────┘
                        │                                       ▲
┌─────────────────┐     │                                       │
│   chat_events   │────▶┘                                       │
│   (Future)      │                                             │
└─────────────────┘                                             │
                        ┌────────────────────────┐              │
                        │  surface_preferences   │◀─────────────┘
                        │      (View)            │
                        │  (✅ Preference Loop)  │
                        └────────────────────────┘
                                 ▲
                                 │
                        ┌─────────────────┐
                        │ app_interactions│
                        │  (✅ Complete)  │
                        └─────────────────┘
```

**Current Implementation**: 
- ✅ Full flow working: HealthKit → State → Intervention → Display → Learning
- ✅ Adaptive feedback loop: User interactions → Preferences → Influence selection
- ⚠️ Target latency: 20-30 seconds (currently ~60s due to polling; push notifications will improve)

**Future Enhancements**:
- Withings integration
- Chat-based interventions
- Push notifications (code exists, needs iOS wiring)

---

## Delivery Model

**Current (Phase 1 - Polling-based)**:
1. `intervention_selector` picks intervention → Creates instance in BigQuery
2. iOS app polls `GET /interventions?user_id=X&status=created` every 60 seconds
3. iOS app fetches and displays intervention banner
4. User interaction → `app_interactions` → `surface_preferences` → influences future selections

**Future (Push-based)**:
1. `intervention_selector` picks intervention → Creates instance
2. Backend sends push notification via APNs (code exists, optional)
3. iOS wakes, fetches full intervention details
4. iOS renders the intervention
5. User interaction → `app_interactions` → learning

**Note**: Push notifications are optional. Polling works without Apple Developer account setup.

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

---

## Project Status

See [STATUS.md](STATUS.md) for detailed implementation status, next steps, and known issues.

---

## Debugging with Traceability

SHIFT includes end-to-end traceability using `trace_id` (UUIDv4) that flows through the entire pipeline from biometrics → watch events → state estimates → interventions → user interactions.

### Finding a trace_id

You can find `trace_id` from:
- **watch_events table**: `SELECT trace_id FROM shift_data.watch_events WHERE user_id = '...' ORDER BY ingested_at DESC LIMIT 1`
- **intervention_instances table**: `SELECT trace_id FROM shift_data.intervention_instances WHERE intervention_instance_id = '...'`
- **state_estimates table**: `SELECT trace_id FROM shift_data.state_estimates WHERE user_id = '...' ORDER BY timestamp DESC LIMIT 1`

### Viewing the full lifecycle

Use the `trace_full_chain` view to reconstruct the complete lifecycle of any intervention:

```sql
SELECT *
FROM shift_data.trace_full_chain
WHERE trace_id = "{trace_id}"
ORDER BY event_timestamp;
```

This view joins all tables on `trace_id` and provides a chronological narrative showing:
- Raw biometrics (watch_events payload)
- State scores (recovery, readiness, stress, fatigue)
- Intervention metadata (metric, level, surface, intervention_key)
- User interaction events (shown, tapped, dismissed)

The view handles NULLs gracefully for backward compatibility with data created before traceability was implemented.
