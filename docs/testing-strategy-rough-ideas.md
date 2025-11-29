# Testing Strategy - Rough Ideas (Iterative)

**Status**: Working ideas, not final implementation plan  
**Purpose**: Capture discussion about testing approach for future reference  
**Last Updated**: 2025-11-25

---

## iOS App Testing

### Idea: "Fake Human" Test App

Create a separate iOS companion app that writes synthetic HealthKit data to test ingestion flows without waiting for real physiological events.

**Structure:**
- Separate Xcode project: `healthkit-test-data/`
- Writes test data to HealthKit (requires write permission)
- SHIFT app reads it via existing HealthKit integration
- Scenario buttons: "High Stress Workout", "Poor Sleep", "Recovery Day", etc.

**Benefits:**
- Test ingestion immediately (no waiting for runs/sleep)
- Test all 17 data types
- Simulate edge cases and scenarios
- Device-agnostic (works with real HealthKit)

**Scenarios to test:**
- High stress workout (HR spike, HRV drop, high energy)
- Poor sleep night (multiple awakenings, low deep sleep)
- Recovery day (low HR, high HRV, minimal activity)
- Withings weigh-in (body composition changes)
- Time-shifted data (simulate days/weeks instantly)

---

## Backend Testing Strategy

### Test Data Generator (Shared)

Python package to generate realistic `HealthDataBatch` objects:

- Scenario generators: `generate_stress_workout()`, `generate_recovery_day()`, etc.
- Matches iOS `HealthDataBatch` schema
- Reusable across iOS test app and backend tests

### FastAPI Endpoint Testing

- pytest with FastAPI TestClient
- Unit tests for Pydantic validation, error handling
- Integration tests with test BigQuery dataset

### SQL Pipeline Testing

- Test `state_estimator` SQL queries against test data
- Verify output tables and scores
- Test edge cases (missing data, nulls)

### Full Flow Testing

End-to-end scenarios:
1. POST health data → FastAPI endpoint
2. Verify BigQuery ingestion
3. Run state estimator
4. Test intervention selector logic

**Structure idea:**
```
pipelines/
├── watch_events/
│   ├── main.py
│   ├── tests/
│   │   ├── test_main.py
│   │   └── fixtures/
├── test_data_generator/  # Shared
│   ├── scenarios.py
│   └── fixtures.py
```

### Testing Patterns

**Unit tests (pytest)**
- Fast, no BigQuery
- Mock dependencies
- Test Pydantic validation
- Test business logic

**Integration tests**
- Real BigQuery test dataset
- Test SQL queries
- Test Pub/Sub → BigQuery flow
- Slower, but closer to production

**Feature/scenario tests**
- Full user journey
- Multi-pipeline flow
- Test state estimation accuracy
- Test intervention selection logic

### Special Considerations

**Pub/Sub testing**
- Option A: Use Pub/Sub emulator (local)
- Option B: Use test Pub/Sub topic in dev project
- Option C: Mock Pub/Sub, test logic only

**BigQuery testing**
- Option A: Test dataset in dev project (recommended)
- Option B: Use `bqtest` or similar library
- Option C: Mock BigQuery client, test SQL separately

**SQL pipeline testing**
- Run SQL against test dataset
- Verify output tables
- Test edge cases (missing data, nulls, etc.)

---

## Notes

- This is a starting point for discussion, not final architecture
- Implementation details will evolve as we build
- Both approaches (iOS test app + backend test data) can work together
- Standard Python testing patterns (pytest, fixtures) apply to backend
- Focus on "feature test coverage" of flows, not 100% unit test coverage
- Goal: Verify main use cases work without long cycle times (jogs, stress induction, etc.)



