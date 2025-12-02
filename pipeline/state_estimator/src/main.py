"""CLI entry point for state estimator pipeline (for local testing)."""

import os
import sys
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.repositories.bigquery_repo import BigQueryRepository
from src.pipeline import run_pipeline


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="State Estimator Pipeline")
    parser.add_argument(
        "--project-id",
        type=str,
        default=os.getenv("GCP_PROJECT_ID"),
        help="GCP project ID",
    )
    parser.add_argument(
        "--dataset-id",
        type=str,
        default="shift_data",
        help="BigQuery dataset ID (default: shift_data)",
    )
    parser.add_argument(
        "--skip-views",
        action="store_true",
        help="Skip creating/updating views",
    )
    parser.add_argument(
        "--skip-transform",
        action="store_true",
        help="Skip transformation",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress verbose output",
    )

    args = parser.parse_args()

    # Initialize repository
    if not args.project_id:
        raise ValueError("--project-id required (or set GCP_PROJECT_ID env var)")
    
    repository = BigQueryRepository(
        project_id=args.project_id,
        dataset_id=args.dataset_id,
    )

    run_pipeline(
        repository=repository,
        create_views=not args.skip_views,
        run_transform=not args.skip_transform,
        verbose=not args.quiet,
    )


# Export for backwards compatibility
from src.pipeline import run_pipeline as _run_pipeline
run_pipeline = _run_pipeline


if __name__ == "__main__":
    main()

