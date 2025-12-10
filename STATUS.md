# SHIFT Project Status

**Last Updated**: December 10, 2025  
**Status**: MVP Adaptive Loop Complete ✅

---

## Executive Summary

The core adaptive intervention loop is **fully implemented and operational**. The system:
- ✅ Ingests health data from iOS/Apple Watch
- ✅ Calculates user state (stress, recovery, readiness, fatigue)
- ✅ Selects interventions adaptively based on user preferences
- ✅ Learns from user interactions and suppresses annoying surfaces
- ✅ Delivers interventions to iOS app via polling

**Overall Progress**: ~90% of MVP complete. Core adaptive loop is operational.

---

## Current Implementation Status

### ✅ Completed Components

#### 1. Data Ingestion Pipeline (`watch_events`)
- Sign in with Apple authentication via GCP Identity Platform
- HealthKit data ingestion from iOS app
- Writes to `watch_events` BigQuery table
- Publishes to `watch_events` Pub/Sub topic

#### 2. State Estimation Pipeline (`state_estimator`)
- SQL-first transformations
- Calculates: `stress`, `recovery`, `readiness`, `fatigue` (0-1 scores)
- Input view: `v_state_estimator_input_v1`
- Output table: `state_estimates`
- Publishes to `state_estimates` Pub/Sub topic
- Repository pattern with mocked tests

#### 3. Intervention Selector Pipeline (`intervention_selector`)
- **Adaptive selection** with preference modeling
- **Data-driven catalog** (BigQuery `intervention_catalog` table)
- **Preference-based scoring** using `surface_preferences` view
- **Suppression logic** (high annoyance surfaces automatically suppressed)
- **Rate limiting** (3 interventions per 30 minutes per user)
- Stress bucketing (high/medium/low)
- Two Cloud Functions:
  - Pub/Sub-triggered: Processes state estimates
  - HTTP-triggered: `GET /interventions/{id}` and `GET /interventions?user_id=X&status=Y`
- APNs push notification support (optional, code exists)

#### 4. iOS App
- Sign in with Apple authentication
- HealthKit integration with background sync
- Intervention polling (60-second intervals)
- Intervention banner display (SwiftUI)
- Interaction tracking (shown, tapped, dismissed)
- Components: `InterventionPoller`, `InterventionBanner`, `InteractionService`, `ApiClient`, `InterventionService`

#### 5. BigQuery Infrastructure
**Tables**:
- `watch_events` (raw HealthKit data)
- `state_estimates` (calculated state scores)
- `intervention_instances` (created interventions)
- `app_interactions` (user interaction events)
- `devices` (device tokens for push notifications)
- `intervention_catalog` (data-driven catalog)

**Views**:
- `trace_full_chain` (end-to-end traceability)
- `surface_preferences` (user preference aggregation)
- `v_state_estimator_input_v1` (state estimator input)
- `v_state_estimator_unprocessed_v1` (unprocessed records)

#### 6. Preference Modeling
- `surface_preferences` BigQuery view aggregates interactions over last 30 days
- Calculates: `engagement_rate`, `annoyance_rate`, `preference_score`
- Event type mapping: iOS events (`"tapped"`, `"dismissed"`) → canonical types (`"tap_primary"`, `"dismiss_manual"`)
- Suppression: Surfaces with `annoyance_rate > 0.7` and `shown_count >= 5` are suppressed
- Selector uses preferences to score and filter candidates

---

## End-to-End Flow

**Current Working Flow**:
1. ✅ iOS app → HealthKit data → `watch_events` pipeline → BigQuery
2. ✅ `state_estimator` → Processes watch_events → Calculates state → Publishes to Pub/Sub
3. ✅ `intervention_selector` → Receives Pub/Sub → Queries catalog → Applies preferences → Selects intervention → Creates instance
4. ✅ iOS app → Polls every 60s → Fetches interventions → Displays banner
5. ✅ User interaction → Recorded to `app_interactions` → Feeds into `surface_preferences` → Influences future selections

**Target latency**: 20-30 seconds (currently ~60s due to polling)

---

## What's Next

### Immediate Priorities (1-2 Weeks)
1. **Expand Intervention Catalog**: Add interventions for recovery/readiness/fatigue metrics
2. **Improve Observability**: Add structured logging, set up monitoring dashboards
3. **Add Test Coverage**: Unit tests for intervention selector
4. **Catalog Management**: Document process for updating catalog

### Short-term Priorities (1 Month)
1. **Push Notifications**: Wire up APNs push notification receiving in iOS (reduce latency to 20-30s)
2. **Multi-Metric Selection**: Extend selector to use recovery/readiness/fatigue, not just stress
3. **In-App Surfaces**: Implement in-app intervention display (not just notification banner)
4. **Production Deployment**: Deploy to production environment

### Medium-term Priorities (1 Quarter)
1. **Withings Integration**: Build `withings_events` pipeline
2. **Advanced Learning**: More sophisticated preference algorithms
3. **A/B Testing Framework**: Test intervention variations
4. **Conversational AI**: Chat-based intervention delivery

---

## Known Issues / Technical Debt

1. **Event type distinction**: iOS doesn't distinguish `dismiss_manual` vs `dismiss_timeout` (all map to `dismiss_manual` for now)
2. **No automated tests**: Intervention selector lacks unit/integration tests
3. **Catalog management**: Manual SQL inserts for now (no UI or sync process)
4. **Logging visibility**: Suppression decisions could be more visible in logs
5. **Polling latency**: 60-second polling adds latency (push notifications would improve this)

---

## Testing Status

### Unit Tests
- ✅ State estimator: Repository pattern with mocked tests
- ❌ Intervention selector: No unit tests yet
- ❌ iOS app: No unit tests yet

### Integration Tests
- ✅ End-to-end flow tested manually
- ✅ Suppression logic verified
- ✅ Preference calculation verified
- ❌ Automated integration tests not yet implemented

---

## Metrics to Monitor

- Intervention creation rate
- Suppression rate (how often surfaces are suppressed)
- Preference scores over time
- Engagement rates by surface
- Annoyance rates by surface
- Rate limiting triggers

---

## Vision Alignment

**SHIFT Vision**: "Better health comes from small, perfectly-timed actions, not dashboards."

**Current State vs Vision**:
- ✅ Ingest wearable data: Complete
- ✅ Real-time state understanding: Complete
- ✅ Select right intervention at right moment: Complete
- ✅ Deliver through native iOS: Complete (MVP, polling-based)
- ❌ Conversational AI: Not started
- ✅ Learning from outcomes: Complete

**We are ~70% aligned with the full vision.** The core adaptive loop is complete, but conversational AI and advanced delivery mechanisms are still future work.

---

**Status**: MVP adaptive loop is **complete and operational**. System is learning from user behavior and adapting intervention selection accordingly.

