# Intervention Selector Pipeline

Selects and delivers interventions based on user state estimates (stress, recovery, etc.).

## Overview

This pipeline follows the SHIFT pipeline pattern:
- **Subscribe** to `state_estimates` Pub/Sub topic (trigger)
- **Read** from `state_estimates` BigQuery table (latest per user)
- **Process**: Bucket stress → Select intervention → Create instance
- **Deliver**: Send push notification via APNs
- **Write**: Store intervention instance in BigQuery

## Architecture

- **Cloud Function (Pub/Sub trigger)**: Processes state estimates and sends interventions
- **Cloud Function (HTTP trigger)**: Provides `GET /interventions/{id}` endpoint for iOS app

## Phase 1 Scope

- **Metrics**: Only `stress` (recovery skipped)
- **Surfaces**: Only `notification` (in_app skipped)
- **Bucketing**: 
  - `high`: stress > 0.7
  - `medium`: 0.3 <= stress <= 0.7
  - `low`: stress < 0.3

## Intervention Catalog

Hard-coded interventions in `src/catalog.py`:

- `stress_high_notification`: "Take a Short Reset"
- `stress_medium_notification`: "Quick Check-in"
- `stress_low_notification`: "Nice Work"

## File Structure

```
intervention_selector/
├── main.py                  # Pub/Sub-triggered Cloud Function
├── http_handler.py          # HTTP-triggered Cloud Function
├── requirements.txt         # Python dependencies
├── pyproject.toml          # Project metadata
└── src/
    ├── catalog.py          # Hard-coded intervention catalog
    ├── bucketing.py        # Stress bucketing logic
    ├── selector.py         # Intervention selection logic
    ├── bigquery_client.py  # BigQuery operations
    └── apns.py             # APNs push notification support
```

## Deployment

Deployed via `deploy.sh` which creates two Cloud Functions:

1. `intervention-selector`: Pub/Sub trigger on `state_estimates` topic
2. `intervention-selector-http`: HTTP trigger for `/interventions/{id}` endpoint

## Environment Variables

- `GCP_PROJECT_ID`: GCP project ID (required)
- `BQ_DATASET_ID`: BigQuery dataset ID (default: `shift_data`)
- `FALLBACK_DEVICE_TOKEN`: Fallback device token for testing (optional)
- `APNS_KEY_ID`: APNs key ID (optional, for push notifications)
- `APNS_TEAM_ID`: APNs team ID (optional)
- `APNS_BUNDLE_ID`: APNs bundle ID (optional, default: `com.shift.ios-app`)
- `APNS_KEY_PATH`: Path to APNs key file (optional)

**Note**: APNs push notifications are **optional for Phase 1**. If not configured:
- Intervention instances are still created in BigQuery
- Status remains "created" (not "failed")
- iOS app can poll the HTTP endpoint to fetch interventions
- No Apple Developer account required for testing

## BigQuery Tables

### intervention_instances

Stores intervention instance records:
- `intervention_instance_id` (STRING, primary key)
- `user_id` (STRING)
- `metric` (STRING)
- `level` (STRING)
- `surface` (STRING)
- `intervention_key` (STRING)
- `created_at` (TIMESTAMP)
- `scheduled_at` (TIMESTAMP)
- `sent_at` (TIMESTAMP, nullable)
- `status` (STRING: "created", "sent", "failed")

### devices

Stores device tokens for push notifications:
- `user_id` (STRING)
- `device_token` (STRING)
- `platform` (STRING)
- `updated_at` (TIMESTAMP)

## Flow

**Phase 1 (Current - Polling-based)**:
1. `state_estimator` creates state estimate → publishes to `state_estimates` Pub/Sub topic
2. `intervention-selector` (Pub/Sub) receives message
3. Queries latest state estimate for user from BigQuery
4. Buckets stress score → Selects intervention
5. Creates intervention instance in BigQuery (status: "created")
6. (Optional) Attempts APNs push notification (if configured)
7. iOS app polls `GET /interventions?user_id=X&status=created` every 60 seconds
8. iOS app displays intervention banner when found

**Future (Push-based)**:
- Steps 1-5 same as above
- APNs push notification sent immediately
- iOS app receives push → calls `GET /interventions/{id}` → displays intervention

## HTTP Endpoints

### `GET /interventions/{intervention_instance_id}`

Returns single intervention instance details including title and body from catalog.

**Use case**: Called by iOS app after receiving push notification (future).

### `GET /interventions?user_id={user_id}&status={status}`

Returns array of intervention instances for a user, filtered by status.

**Query parameters**:
- `user_id` (required): User ID to fetch interventions for
- `status` (optional, default: "created"): Filter by status ("created", "sent", "failed")

**Use case**: Called by iOS app polling service every 60 seconds (Phase 1 primary method).

**Example response**:
```json
{
  "interventions": [
    {
      "intervention_instance_id": "uuid",
      "user_id": "user123",
      "metric": "stress",
      "level": "high",
      "surface": "notification",
      "intervention_key": "stress_high_notification",
      "title": "Take a Short Reset",
      "body": "You seem overloaded. Take a 5-minute break.",
      "created_at": "2025-01-01T12:00:00Z",
      "scheduled_at": "2025-01-01T12:00:00Z",
      "sent_at": null,
      "status": "created"
    }
  ]
}
```

Example response:
```json
{
  "intervention_instance_id": "uuid",
  "user_id": "user123",
  "metric": "stress",
  "level": "high",
  "surface": "notification",
  "intervention_key": "stress_high_notification",
  "title": "Take a Short Reset",
  "body": "You seem overloaded. Take a 5-minute break.",
  "created_at": "2025-01-01T12:00:00Z",
  "scheduled_at": "2025-01-01T12:00:00Z",
  "sent_at": "2025-01-01T12:00:01Z",
  "status": "sent"
}
```

## Error Handling

- If APNs not configured: Status remains "created", logged as info (not an error)
- If APNs fails: Status remains "created", logged as warning (can retry later)
- If device token missing: Status remains "created", logged as info
- If stress is NULL: No intervention selected

## Phase 1 Delivery: Polling vs Push

**Current Implementation (Phase 1)**: Polling-based delivery
- iOS app polls `GET /interventions?user_id=X&status=created` every 60 seconds
- No Apple Developer account required
- Works immediately without APNs setup
- Easier to test and debug
- See `INTERVENTION_POLLING_IMPLEMENTATION.md` for iOS implementation details

**Future Enhancement**: Push-based delivery
- APNs push notifications sent immediately when intervention created
- iOS app receives push → calls `GET /interventions/{id}` → displays intervention
- Requires Apple Developer account and APNs configuration
- Code exists but not required for Phase 1

## Testing Without Apple Developer Account

For Phase 1 testing without an Apple Developer account:

1. **Skip APNs entirely** - Don't set APNs env vars
2. **Intervention instances are still created** in BigQuery (status: "created")
3. **Use polling endpoint** - iOS app polls `GET /interventions?user_id=X&status=created`
4. **Check logs** - Cloud Function logs will show intervention creation

Example flow:
```
1. State estimate created → Pub/Sub message
2. Intervention selector creates instance in BigQuery
3. Status: "created" (push not sent, APNs optional)
4. iOS app polls list endpoint every 60 seconds
5. iOS app displays intervention banner when found
```

