"""Cloud Function entry point for state estimator pipeline."""

import base64
import json
import logging
import os
from cloudevents.http import CloudEvent
import functions_framework

from src.repositories.bigquery_repo import BigQueryRepository
from src.pipeline import run_pipeline

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@functions_framework.cloud_event
def state_estimator(cloud_event: CloudEvent):
    """Cloud Function triggered by Pub/Sub message.
    
    Args:
        cloud_event: CloudEvent from Pub/Sub
    """
    try:
        # Extract message data from Pub/Sub CloudEvent
        # Pub/Sub messages in Cloud Functions 2nd gen come as base64-encoded data
        message_data = cloud_event.get_data()
        if message_data:
            if isinstance(message_data, bytes):
                decoded_data = base64.b64decode(message_data).decode("utf-8")
                try:
                    payload = json.loads(decoded_data)
                    logger.info(f"Received Pub/Sub message: {payload}")
                except json.JSONDecodeError:
                    logger.info(f"Received Pub/Sub message (non-JSON): {decoded_data}")
            elif isinstance(message_data, dict):
                logger.info(f"Received Pub/Sub message: {message_data}")
        
        # Initialize repository
        project_id = os.getenv("GCP_PROJECT_ID")
        if not project_id:
            raise ValueError("GCP_PROJECT_ID environment variable not set")
        
        dataset_id = os.getenv("BQ_DATASET_ID", "shift_data")
        repository = BigQueryRepository(
            project_id=project_id,
            dataset_id=dataset_id,
        )
        
        # Run pipeline (processes all unprocessed records)
        logger.info("Starting state estimator pipeline...")
        run_pipeline(
            repository=repository,
            create_views=True,
            run_transform=True,
            verbose=True,
        )
        
        logger.info("State estimator pipeline completed successfully")
        
    except Exception as e:
        logger.error(f"Error in state estimator pipeline: {e}", exc_info=True)
        raise  # Re-raise to trigger Cloud Function retry mechanism

