# SHIFT Implementation Status

**Last Updated**: 2025-12-02

## 🎯 Core Pipeline: Data → State → Intervention

### ✅ **Pipeline 1: Watch Events Ingestion** (COMPLETE & WORKING)

**Service**: Cloud Run (`watch-events`)  
**Location**: `pipeline/watch_events/`

**What it does**:
- Receives HealthKit data from iOS app via POST `/watch_events`
- Authenticates users via Sign in with Apple (Identity Platform integration)
- Deduplicates events using Firestore (key: `user_{id}:time_{fetchedAt}`)
- Writes raw events to BigQuery `watch_events` table (streaming insert)
- Publishes lightweight trigger message to `watch_events` Pub/Sub topic

**Status**: ✅ **FULLY OPERATIONAL**
- Service deployed and accessible
- Authentication working
- BigQuery writes confirmed
- Pub/Sub publishing confirmed

**Infrastructure**:
- BigQuery table: `shift_data.watch_events`
- Pub/Sub topic: `watch_events`
- Firestore database: Deduplication keys
- Service account: `watch-events-sa` (Firestore, BigQuery, Pub/Sub permissions)

---

### ✅ **Pipeline 2: State Estimator** (COMPLETE & WORKING)

**Service**: Cloud Function (2nd gen) (`state-estimator`)  
**Location**: `pipeline/state_estimator/`

**What it does**:
- Triggered by Pub/Sub messages on `watch_events` topic
- Reads from `watch_events` BigQuery table
- Transforms raw HealthKit data into state estimates using SQL:
  - **Recovery**: Based on HRV, resting HR, sleep quality (0-1 score)
  - **Readiness**: Recovery + recent activity levels (0-1 score)
  - **Stress**: Lower HRV = higher stress, elevated HR (0-1 score)
  - **Fatigue**: Sleep duration/quality, workout intensity (0-1 score)
- Writes to `state_estimates` BigQuery table (one row per user per timestamp)
- Publishes message to `state_estimates` Pub/Sub topic after successful write

**Status**: ✅ **FULLY OPERATIONAL**
- Cloud Function deployed and triggered successfully
- State estimates created correctly (verified via test script)
- SQL transformations producing valid scores
- Pub/Sub publishing to `state_estimates` topic working

**Infrastructure**:
- BigQuery table: `shift_data.state_estimates`
- Pub/Sub topic: `state_estimates`
- Service account: `state-estimator-sa` (BigQuery, Pub/Sub permissions)
- SQL files: `sql/views.sql`, `sql/transform.sql`

---

### ⚠️ **Pipeline 3: Intervention Selector** (DEPLOYED, DEBUGGING)

**Service**: Cloud Functions (2nd gen)
- `intervention-selector` (Pub/Sub trigger)
- `intervention-selector-http` (HTTP trigger)

**Location**: `pipeline/intervention_selector/`

**What it does**:
- **Pub/Sub Function**: Triggered by messages on `state_estimates` topic
  - Reads latest state estimate per user from BigQuery
  - Buckets stress score into `high` (>0.7), `medium` (0.3-0.7), `low` (<0.3)
  - Selects intervention from hard-coded catalog (stress-based only for Phase 1)
  - Creates intervention instance in `intervention_instances` BigQuery table
  - Attempts to send APNs push notification (optional - logs if not configured)
  - Updates intervention instance status (`created`/`sent`/`failed`)
- **HTTP Function**: Provides `GET /interventions/{id}` endpoint
  - iOS app calls this after receiving push notification
  - Returns intervention details (title, body, metadata)

**Status**: ⚠️ **DEPLOYED BUT NOT CREATING INTERVENTIONS YET**
- Cloud Functions deployed successfully
- Receiving Pub/Sub messages (confirmed in logs)
- **Issue**: Message payload parsing issue (extracting `user_id`/`timestamp` from CloudEvent envelope)
- **Fix in progress**: Updated code to properly decode Pub/Sub CloudEvent structure

**Infrastructure**:
- BigQuery tables:
  - `shift_data.intervention_instances` (created)
  - `shift_data.devices` (created, for device tokens)
- Pub/Sub topic: `state_estimates` (subscribed)
- Service account: `intervention-selector-sa` (BigQuery, Pub/Sub permissions)
- IAM bindings: Eventarc service account + function SA have `roles/run.invoker`

**Phase 1 Scope**:
- Metrics: **stress only** (recovery skipped)
- Surfaces: **notification only** (in_app skipped)
- Bucketing thresholds: Hard-coded constants
- Catalog: Hard-coded in `src/catalog.py`
- APNs: Optional (logs warning if not configured)

---

## 📱 iOS App

**Location**: `ios_app/`

**What's implemented**:
- HealthKit integration: Reads steps, HRV, resting HR, sleep data
- Authentication: Sign in with Apple integration (Identity Platform backend)
- API client: Posts HealthKit data to `/watch_events` endpoint
- Sync coordinator: Handles data fetching and posting logic

**Status**: ✅ **BASIC FUNCTIONALITY WORKING**
- Can authenticate and post data to backend
- Push notification handling: **NOT YET IMPLEMENTED**

---

## 🏗️ Infrastructure (Terraform)

**Location**: `terraform/projects/dev/`

**What's managed**:
- **GCP Services Enabled**: Identity Platform, Cloud Run, IAM, Secret Manager, Firestore, BigQuery, Pub/Sub
- **Service Accounts**:
  - `watch-events-sa`
  - `state-estimator-sa`
  - `intervention-selector-sa`
- **BigQuery**:
  - Dataset: `shift_data`
  - Tables: `watch_events`, `state_estimates`, `intervention_instances`, `devices`
- **Pub/Sub Topics**: `watch_events`, `state_estimates`
- **Cloud Run**: `watch-events` service
- **IAM**: All service account permissions configured

**Status**: ✅ **FULLY PROVISIONED**
- All resources created via Terraform
- IAM bindings correct
- Service accounts have appropriate permissions

---

## 🧪 Testing

### End-to-End Test Script
**Location**: `test_pipeline.sh`

**What it does**:
1. Inserts test `watch_events` row into BigQuery
2. Publishes message to `watch_events` Pub/Sub topic (triggers state_estimator)
3. Waits and verifies `state_estimates` row created
4. Inserts high-stress `state_estimates` row (stress = 0.95)
5. Publishes message to `state_estimates` Pub/Sub topic (triggers intervention_selector)
6. Waits and verifies `intervention_instances` row created

**Status**: ✅ **SCRIPT COMPLETE**, ⚠️ **STEP 6 FAILING**
- Steps 1-3 working perfectly ✅
- Step 6 not creating intervention instances (due to payload parsing issue)

### Unit Tests
**Location**: `pipeline/state_estimator/tests/`

**What's tested**:
- SQL view creation
- State estimation transformations
- Repository pattern (BigQuery implementation)

**Status**: ✅ **TESTS EXIST AND PASS**

---

## 📊 Data Flow (Current State)

```
iOS App (HealthKit)
  ↓ POST /watch_events
watch-events Cloud Run
  ↓ (dedupe via Firestore)
BigQuery: watch_events
  ↓ (streaming insert)
Pub/Sub: watch_events topic
  ↓ (trigger)
state-estimator Cloud Function
  ↓ (SQL transformation)
BigQuery: state_estimates
  ↓ (publish)
Pub/Sub: state_estimates topic
  ↓ (trigger)
intervention-selector Cloud Function
  ↓ (select & create)
BigQuery: intervention_instances ❌ (NOT WORKING YET)
  ↓ (send push)
APNs → iOS App (NOT YET IMPLEMENTED)
```

---

## 🚀 Deployment

**Script**: `deploy.sh`

**What it does**:
1. Validates Terraform
2. Applies Terraform (creates infrastructure)
3. Builds and pushes container images (watch-events)
4. Deploys Cloud Run services (watch-events)
5. Deploys Cloud Functions (state-estimator, intervention-selector, intervention-selector-http)

**Status**: ✅ **WORKING**
- All services deploy successfully
- Infrastructure provisioning automated
- Single command deployment: `./deploy.sh -b`

---

## ❌ Not Yet Implemented

### Pipelines (Future)
- `withings_events`: Withings API → BigQuery
- `chat_events`: Conversational agent → BigQuery
- `app_interactions`: iOS gestures/reactions → BigQuery
- `interaction_preferences`: User preference learning pipeline

### Features
- **APNs Push Notifications**: Code exists but not configured/tested
- **iOS Push Notification Handling**: App doesn't handle push yet
- **Intervention Catalog**: Currently hard-coded, future: Google Sheets sync
- **Learning Loop**: No feedback mechanism yet (completions, dismissals)

---

## 🐛 Known Issues

1. **Intervention Selector Payload Parsing**: CloudEvent structure from Pub/Sub needs proper decoding (fix in progress)
2. **IAM Propagation**: Some IAM bindings may need time to propagate after deployment

---

## 📝 Next Steps

1. **Fix intervention-selector payload parsing** (in progress)
2. **Verify intervention_instances table gets rows created**
3. **Configure APNs credentials** (Apple Developer account required)
4. **Test push notification delivery**
5. **Implement iOS push notification handling**
6. **Add interaction tracking** (when user taps/closes notification)

