"""Pipeline execution logic for state estimator."""

import logging
from pathlib import Path

logger = logging.getLogger(__name__)


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
            logger.info("[State Estimator] Creating/updating views...")
        views_path = sql_dir / "views.sql"
        repository.execute_script(views_path, verbose=verbose)
        if verbose:
            logger.info("[State Estimator] Views created/updated successfully")

    if run_transform:
        if verbose:
            logger.info("[State Estimator] Running transformation...")
        transform_path = sql_dir / "transform.sql"
        repository.execute_script(transform_path, verbose=verbose)
        if verbose:
            logger.info("[State Estimator] Transformation completed successfully")

