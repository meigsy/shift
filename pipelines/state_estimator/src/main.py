"""Main entry point for state estimator pipeline."""

import os
import sys
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from src.repositories.bigquery_repo import BigQueryRepository


def run_pipeline(
    repository,
    create_views: bool = True,
    run_transform: bool = True,
    verbose: bool = True,
):
    """Run the state estimator pipeline.

    Args:
        repository: Repository instance (implements Repository protocol)
        create_views: Whether to create/update views
        run_transform: Whether to run transformation
        verbose: Whether to print progress
    """
    base_path = Path(__file__).parent.parent
    sql_dir = base_path / "sql"

    if create_views:
        if verbose:
            print("[State Estimator] Creating/updating views...")
        views_path = sql_dir / "views.sql"
        repository.execute_script(views_path, verbose=verbose)
        if verbose:
            print("[State Estimator] Views created/updated successfully")

    if run_transform:
        if verbose:
            print("[State Estimator] Running transformation...")
        transform_path = sql_dir / "transform.sql"
        repository.execute_script(transform_path, verbose=verbose)
        if verbose:
            print("[State Estimator] Transformation completed successfully")


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


if __name__ == "__main__":
    main()

