# SHIFT Fitness OS

**An ELT-driven health behavior system: Apple Watch + Withings → pipelines → state → agent (LangChain) → iOS delivery.**

---

## Vision

SHIFT is a **personal health operating system**:

- Ingest wearable + lifestyle data
- Maintain real-time understanding of user state (recovery, fatigue, readiness, stress)
- Select the right micro-intervention at the right moment
- Deliver through native iOS + conversational AI

**Core philosophy**: Better health comes from *small, perfectly-timed actions*, not dashboards.

**Flow**: Data → State → Agent (context-aware decisions) → Delivery → Learning → Refinement

**Status**: ✅ End-to-end pipeline operational. All infrastructure in Terraform. See `DEVELOPMENT.md` for progress tracking.

---

## Architecture

### System Flow

```
WATCH → HealthKit → iPhone → Pub/Sub → State Estimator → BigQuery (state_estimates)
                                                                    ↓
User/System Events → Agent (LangChain 1.0) → iOS
                       ↑
              Middleware (gating, context injection)
```

### Architecture Philosophy

**Key Principle:**
- **Data Pipelines** handle ELT (Extract, Load, Transform) - deterministic processing
- **Agent** handles decisions (what to do, when to notify, how to respond) - context-aware orchestration

### Layers

1. **Input** — Wearables, chat, app interactions
2. **State Estimation** — SQL pipelines infer recovery/readiness/stress/fatigue (stored in BigQuery)
3. **Agent Orchestration** — LangChain 1.0 agent with middleware stack makes context-aware decisions
4. **Delivery** — Agent responses via `/chat` or `/tool_event`, push notifications when appropriate
5. **Learning** — User interactions update agent context via `update_user_context` tool

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
│   └── conversational_agent/   # LangChain 1.0 agent service (✅ operational)
│       ├── Agent orchestration (GROW coaching model)
│       ├── Middleware stack (gating, context injection)
│       └── Tools (update_user_context, send_notification)
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
| `state_estimator` | All events | stress, recovery, fatigue, readiness scores (BigQuery) |
| `conversational_agent` | State estimates + user events + conversation | Agent decisions and responses |

### Agent Service

The `conversational_agent` pipeline is the orchestration layer for all user interactions:

- **Endpoints:**
  - `/chat` - User text messages (SSE streaming)
  - `/tool_event` - Structured events from iOS (card taps, app lifecycle, flow completions)
  
- **Middleware Stack:**
  - `NotificationGatingMiddleware` - Deterministic filtering (preferences, quiet hours, rate limits)
  - `ContextInjectionMiddleware` - Progressive context disclosure (profile, goals, recent events, conversation)
  
- **Tools:**
  - `update_user_context` - Agent maintains user state (profile, goals, context) in Firestore
  - `send_notification` - Proactive push notifications when warranted
  
- **Data Storage:**
  - **Firestore**: Agent state (user context, conversation history) - fast reads/writes
  - **BigQuery**: Analytics (state estimates, app interactions) - batch reads for context injection

---

## Event Flow

```
┌─────────────────┐
│  watch_events   │────▶┐
└─────────────────┘     │
                        │
┌─────────────────┐     │     ┌─────────────────┐     ┌──────────────────────┐
│ withings_events │────▶├────▶│ state_estimator │────▶│   BigQuery           │
└─────────────────┘     │     └─────────────────┘     │   (state_estimates)  │
                        │                               └──────────────────────┘
┌─────────────────┐     │                                       │
│   chat_events   │────▶┘                                       │
└─────────────────┘                                             │
                                                                 │
┌─────────────────┐     ┌──────────────────────────┐          │
│ app_interactions│────▶│  Agent (LangChain 1.0)    │◀─────────┘
└─────────────────┘     │  + Middleware Stack        │
                        │  + Context Injection       │
┌─────────────────┐     │  + Tools                   │
│  /tool_event    │────▶└──────────────────────────┘
│  (iOS events)   │              │
└─────────────────┘              │
                                 │
                        ┌─────────▼─────────┐
                        │  /chat responses  │
                        │  Push notifications│
                        └───────────────────┘
```

**Pipeline Flow:**
1. Watch → `watch_events` → BigQuery (raw data)
2. BigQuery → `state_estimator` (Pub/Sub triggered) → `state_estimates` table
3. Agent middleware reads `state_estimates` for context injection
4. User events (`/tool_event`, `/chat`) → Agent → Responses/Notifications

Target latency: **20–30 seconds** for data pipeline, **<2 seconds** for agent responses (p95).

---

## Agent Service Endpoints

### `/chat` (User Messages)

**Endpoint**: `POST /chat` (SSE streaming)

**Purpose**: Receives user text messages and returns agent responses via Server-Sent Events.

**Request Schema:**
```json
{
  "message": "I'm feeling really stressed today",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

**Response**: Streams agent response as SSE chunks.

**Authentication**: User identity derived from Bearer token in Authorization header.

### `/tool_event` (Structured Events)

**Endpoint**: `POST /tool_event`

**Purpose**: Receives structured events from iOS and background systems. Agent processes these to make context-aware decisions.

**Event Types:**
- `app_opened_first_time` - User's first app launch
- `app_opened` - Subsequent app launches
- `card_tapped` - User engaged with an intervention card
- `rating_submitted` - User provided structured input (1-5 rating)
- `health_metric_changed` - Background pipeline detected significant change
- `flow_completed` - User completed a multi-step flow (e.g., getting_started)

**Request Schema:**
```json
{
  "type": "card_tapped",
  "intervention_key": "stress_checkin",
  "suggested_action": "rate_stress_1_to_5",
  "context": "User tapped stress check-in card",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

**Response:**
```json
{
  "message": "Quick check-in: How stressed do you feel (0-10)?",
  "ui_hint": "rating_scale",
  "metadata": {
    "conversation_id": "uuid",
    "requires_response": true
  }
}
```

### Agent Middleware Stack

**NotificationGatingMiddleware:**
- Deterministic filtering before agent invocation
- Gates: user preferences, quiet hours, rate limits (4-hour minimum between notifications)
- Returns `None` to short-circuit (no LLM call) or `state` to continue

**ContextInjectionMiddleware:**
- Progressive context disclosure into agent prompt
- Layers: Profile (stable), Global Goals (long-term), Current Focus (active plans), Recent Events (7-day window), Conversation (token-limited)
- Loads from Firestore (user context) and BigQuery (state estimates, interactions)

### Agent Tools

**update_user_context:**
- Agent maintains complete user state (Profile, Goals, Context)
- Updates stored in Firestore for fast access
- Agent decides what changed based on conversation

**send_notification:**
- Proactive push notifications when warranted
- Only used when: user preferences allow, event is significant, message provides clear value
- Gated by middleware to prevent spam

---

## App UX Surfaces (MVP)

### Chat-First Architecture

The iOS app is built around a **chat-first** experience where the conversational agent is the primary interface:

- **Chat View** - Primary surface, always accessible
- **Cards** - Ephemeral affordances that trigger agent conversations via `/tool_event`
- **Side Panel** - Utility overlay (new chat, past chats, settings)

### Card → Agent Flow

When a user interacts with a card:

1. iOS sends `/tool_event` with structured event (e.g., `card_tapped`, `flow_completed`)
2. Agent receives event via middleware (context injection, gating)
3. Agent responds with appropriate message or action
4. Response streams to iOS via `/chat` endpoint (SSE)
5. iOS displays agent response in chat interface

**Key Principle**: Cards don't collect input or replace chat. They initiate agent conversations.

### Conversation Phases

The agent navigates users through three phases:

1. **[Intake]** - Gather profile information (name, age, experience level, preferences)
2. **[Global Goals]** - Define long-term objectives (healthspan targets, timeline, milestones)
3. **[Check-ins]** - Ongoing GROW-based guidance (daily/weekly conversations, workout prep, progress tracking)

Agent detects which phase the user is in and gathers missing information before advancing.

### Getting Started Flow

The existing multi-page onboarding flow (`getting_started`) is preserved:

- User completes onboarding pages
- On "Start" button tap, iOS sends `/tool_event` with `flow_completed` event
- Agent recognizes intake phase complete, initiates global goals conversation

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

- **Chat View** - Primary conversational interface (SSE streaming)
- **Cards** - Ephemeral triggers that send `/tool_event` to agent
- **Push notifications** - Agent-initiated via `send_notification` tool (when warranted)
- **Side Panel** - Utility overlay (chat management, settings)

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

## Data Storage Architecture

### Firestore (Agent State, Real-time Access)

**Collections:**
- `user_context/{user_id}` - UserGoalsAndContext object (Profile, Goals, Context)
  - Fast reads on every agent invocation
  - Writes via `update_user_context` tool
- `agent_conversations/{user_id}/messages` - LangChain checkpointing
  - Conversation history
  - Managed by LangGraph persistence

**Access Pattern:** Read/write on every agent interaction (low latency required)

### BigQuery (Analytics, Historical Data)

**Tables:**
- `state_estimates` - Pipeline-generated health metrics
  - Written by state_estimator (Pub/Sub triggered)
  - Read by agent for recent context (via middleware)
- `app_interactions` - Event log
  - All tool_events and chat messages
  - Used for analytics and conversation summarization
- `watch_events` - Raw biometric data from HealthKit

**Access Pattern:** Batch reads for context injection, async writes for logging

## Debugging with Traceability

SHIFT includes end-to-end traceability using `trace_id` (UUIDv4) that flows through the entire pipeline from biometrics → watch events → state estimates → agent decisions → user interactions.

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

---

## Testing End-to-End Flow

The `test_e2e_hrv.sh` script runs a complete synthetic end-to-end test of the entire pipeline.

### Running the Test

```bash
./test_e2e_hrv.sh
```

### What It Tests

The script exercises the full lifecycle:

1. **watch_events** → POSTs synthetic HRV data (HRV=25ms, RestingHR=75bpm) to trigger high stress
2. **state_estimator** → Polls BigQuery until state estimate appears (stress score ~0.86)
3. **intervention_selector** → Polls BigQuery until intervention instance is created
4. **BigQuery query** → Queries `intervention_instances` table directly for intervention details
5. **app_interactions** → POSTs three interaction events (shown, tapped, dismissed)
6. **Verification** → Queries all tables and `trace_full_chain` view to verify full traceability

### Expected Output

The script prints:
- Step-by-step progress through each pipeline stage
- BigQuery query results showing data at each stage
- Full lifecycle summary with trace_id for further investigation

The test uses synthetic data with `trace_id` for complete traceability from HRV reading → intervention → user interaction.
