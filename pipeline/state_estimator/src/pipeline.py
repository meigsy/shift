"""Pipeline execution logic for state estimator."""

import json
import logging
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

logger = logging.getLogger(__name__)


def publish_state_estimates(
    repository,
    project_id: str,
    topic_name: str = "state_estimates",
    verbose: bool = True,
):
    """Publish newly created state estimates to Pub/Sub.

    Args:
        repository: Repository instance (implements Repository protocol)
        project_id: GCP project ID
        topic_name: Pub/Sub topic name (default: state_estimates)
        verbose: Whether to print progress
    """
    try:
        from google.cloud import pubsub_v1

        publisher = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(project_id, topic_name)

        if verbose:
            logger.info(f"[State Estimator] Querying newly created state estimates...")

        # Query for the latest state estimate per user created in the last 5 minutes
        # This captures newly created estimates from the transform
        query = """
            WITH cte_latest_per_user AS (
                SELECT
                    user_id,
                    timestamp,
                    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY timestamp DESC) as rn
                FROM `{project_id}.shift_data.state_estimates`
                WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
            )
            SELECT user_id, timestamp
            FROM cte_latest_per_user
            WHERE rn = 1
        """.format(project_id=project_id)

        results = repository.execute_query(query, verbose=False)

        published_count = 0
        for row in results:
            user_id = row.user_id
            timestamp = row.timestamp

            # Publish message with user_id and timestamp
            message_data = {
                "user_id": user_id,
                "timestamp": timestamp.isoformat(),
            }
            data = json.dumps(message_data).encode("utf-8")

            future = publisher.publish(topic_path, data)
            message_id = future.result()

            if verbose:
                logger.info(
                    f"[State Estimator] Published state estimate for user {user_id} at {timestamp} (message_id: {message_id})"
                )
            published_count += 1

        if verbose:
            logger.info(f"[State Estimator] Published {published_count} state estimate(s) to Pub/Sub")

    except Exception as e:
        # Log error but don't fail the pipeline
        logger.warning(f"[State Estimator] Failed to publish state estimates to Pub/Sub: {e}")


def run_pipeline(
    repository,
    create_views: bool = True,
    run_transform: bool = True,
    publish_results: bool = True,
    verbose: bool = True,
):
    """Run the state estimator pipeline.

    Args:
        repository: Repository instance (implements Repository protocol)
        create_views: Whether to create/update views
        run_transform: Whether to run transformation
        publish_results: Whether to publish results to Pub/Sub
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

        # Publish newly created state estimates to Pub/Sub
        if publish_results:
            project_id = os.getenv("GCP_PROJECT_ID")
            if project_id:
                publish_state_estimates(repository, project_id, verbose=verbose)
            elif verbose:
                logger.warning("[State Estimator] GCP_PROJECT_ID not set, skipping Pub/Sub publish")


