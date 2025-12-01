# State Estimator Pipeline

Transforms `watch_events` data into state estimates (recovery, readiness, stress, fatigue) using SQL-first transformations.

## Overview

This pipeline follows the meigsy ai system patterns:
- Input view: `v_state_estimator_input_v1` - extracts/flattens data from `watch_events`
- Unprocessed view: `v_state_estimator_unprocessed_v1` - filters new/unprocessed records
- Output table: `state_estimates` - stores calculated state scores

## Architecture

- **Repository Pattern**: Abstract interface for database operations
  - `BigQueryRepository`: Production implementation (only implementation)
- **SQL-first**: All transformations in SQL files
- **Minimal Python**: Just orchestrates SQL execution
- **Mocked Tests**: Unit tests use mocked repository (no DB needed)

## Prerequisites

- Python 3.11+
- `uv` for package management
- GCP project with BigQuery enabled

## Setup

```bash
cd pipeline/state_estimator
uv sync
```

## Usage

### Production (BigQuery)

```bash
# Set GCP project
export GCP_PROJECT_ID=your-project-id

# Run pipeline
uv run python -m src.main --project-id $GCP_PROJECT_ID
```

### Local Testing

```bash
# Install dev dependencies
uv sync --extra dev

# Run tests (uses mocked repository)
uv run pytest
```

## State Estimation Logic

Simple formulas based on available health metrics:

- **Recovery**: HRV (higher = better), resting HR (lower = better), sleep quality
- **Readiness**: Recovery + recent activity levels (workouts, steps)
- **Stress**: Lower HRV = higher stress, elevated HR
- **Fatigue**: Sleep duration/quality, recent workout intensity, low activity

All scores are normalized to 0-1 range.

## File Structure

```
pipeline/state_estimator/
├── sql/
│   ├── views.sql            # View definitions (input, unprocessed)
│   └── transform.sql        # Main transformation logic
├── src/
│   ├── main.py              # Entry point
│   ├── repository.py        # Repository interface
│   └── repositories/
│       └── bigquery_repo.py # BigQuery implementation
├── tests/
│   ├── conftest.py          # Test fixtures
│   ├── test_pipeline.py     # Integration tests
│   └── fixtures/            # Test data
└── pyproject.toml           # Dependencies
```

## SQL Files

### views.sql

Defines:
- `v_state_estimator_input_v1`: Extracts and aggregates metrics from `watch_events` JSON payload
- `v_state_estimator_unprocessed_v1`: Filters records not yet processed (LEFT JOIN pattern)

### transform.sql

Reads from unprocessed view, calculates state scores, and inserts into `state_estimates` table.

## Testing

Tests use mocked repository for fast, local execution without BigQuery dependencies. SQL testing should be done manually in BigQuery console or via integration tests against real BigQuery.

```bash
# Run all tests
uv run pytest

# Run with verbose output
uv run pytest -v

# Run specific test
uv run pytest tests/test_pipeline.py::test_run_pipeline_executes_views_and_transform
```

**Note**: SQL logic should be tested manually in BigQuery console or via integration tests. Unit tests verify Python orchestration logic only.

## Output Schema

The `state_estimates` table has the following schema:

- `user_id` (STRING, REQUIRED): User identifier
- `timestamp` (TIMESTAMP, REQUIRED): When the estimate was generated (matches `fetched_at`)
- `recovery` (FLOAT64): Recovery score (0-1)
- `readiness` (FLOAT64): Readiness score (0-1)
- `stress` (FLOAT64): Stress score (0-1)
- `fatigue` (FLOAT64): Fatigue score (0-1)

## Notes

- Per-batch processing: Generates estimates for each `watch_events` batch
- Idempotent: Safe to re-run (unprocessed view filters already-processed records)
- SQL-first: All business logic in SQL, Python just orchestrates execution

