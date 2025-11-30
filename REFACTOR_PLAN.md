# Refactor: Simplified Ingestion Pipeline

**Goal**: Simplify iOS app logic (dumb fire-and-forget) and move deduplication and storage to the backend using a synchronous "Direct Write" pattern.

## Status: COMPLETED

## Architecture

**Flow**:
`iOS (POST)` → `Backend (FastAPI)` → `Firestore (Dedupe)` → `BigQuery (Write)` → `Pub/Sub (Trigger)`

1.  **iOS App**:
    - Removes all sync locking, debouncing, and state tracking.
    - Simply POSTs to `/watch_events` whenever HealthKit data is detected.
    - Fire-and-forget.

2.  **Backend (`POST /watch_events`)**:
    - **Deduplication**: Generates key `user_{id}:time_{fetchedAt}`. Checks Firestore.
        - If exists: Returns 200 OK immediately.
        - If new: Writes key to Firestore (TTL 1 hour).
    - **Storage**: Writes payload directly to BigQuery `watch_events` table (Streaming Insert).
    - **Trigger**: Publishes lightweight message to `data_ingested` Pub/Sub topic (for future State Estimator).
    - Returns 200 OK.

## Implementation Steps

### 1. Terraform (`terraform/projects/dev/`)
- [x] Enable APIs: `firestore.googleapis.com`, `bigquery.googleapis.com`, `pubsub.googleapis.com`
- [x] Create BigQuery Dataset (`shift_data`) and Table (`watch_events`)
- [x] Create Pub/Sub Topic (`data_ingested`)
- [x] Create Firestore Database (`(default)`)
- [x] Grant Service Account permissions (Firestore User, BQ Data Editor, Pub/Sub Publisher)

### 2. Backend (`backend/`)
- [x] Add dependencies: `google-cloud-firestore`, `google-cloud-bigquery`, `google-cloud-pubsub`
- [x] Update `main.py`:
    - Initialize clients (Firestore, BQ, Pub/Sub)
    - Implement Dedupe logic in `/watch_events`
    - Implement BQ Write logic
    - Implement Pub/Sub Publish logic
- [x] Update `requirements.txt`

### 3. iOS App (`ios_app/`)
- [x] Remove `SyncService` locking/debouncing logic.
- [x] Verify "dumb" posting works against new backend.
