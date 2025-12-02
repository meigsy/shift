"""Cloud Function entry point for intervention selector pipeline."""

import base64
import json
import logging
import os
from datetime import datetime, timezone
from typing import Dict, Any

from cloudevents.http import CloudEvent
import functions_framework

from src.bigquery_client import BigQueryClient
from src.selector import select_intervention
from src.catalog import get_intervention
from src.apns import send_push_notification

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def process_state_estimate(user_id: str, timestamp: str) -> None:
    """Process a state estimate and create/send intervention if needed.

    Args:
        user_id: User ID
        timestamp: State estimate timestamp (ISO format)
    """
    project_id = os.getenv("GCP_PROJECT_ID")
    if not project_id:
        raise ValueError("GCP_PROJECT_ID environment variable not set")

    dataset_id = os.getenv("BQ_DATASET_ID", "shift_data")
    bq_client = BigQueryClient(project_id=project_id, dataset_id=dataset_id)

    # Get latest state estimate for user (should match the timestamp from Pub/Sub)
    state_estimate = bq_client.get_latest_state_estimate(user_id)
    if not state_estimate:
        logger.warning(f"No state estimate found for user {user_id}")
        return

    # Verify this is the state estimate we're processing
    if state_estimate["timestamp"].isoformat() != timestamp:
        logger.warning(
            f"State estimate timestamp mismatch: expected {timestamp}, got {state_estimate['timestamp'].isoformat()}"
        )

    # Select intervention based on stress
    intervention = select_intervention(state_estimate.get("stress"))
    if not intervention:
        logger.info(f"No intervention selected for user {user_id}")
        return

    # Create intervention instance
    intervention_instance_id = bq_client.create_intervention_instance(
        user_id=user_id,
        metric=intervention["metric"],
        level=intervention["level"],
        surface=intervention["surface"],
        intervention_key=intervention["intervention_key"],
    )

    # Get device token (from table or fallback env var)
    device_token = bq_client.get_device_token(user_id)
    if not device_token:
        # Try fallback from env var
        device_token = os.getenv("FALLBACK_DEVICE_TOKEN")

    # Send push notification (optional - will log warning if APNs not configured)
    if device_token:
        success = send_push_notification(
            device_token=device_token,
            title=intervention["title"],
            body=intervention["body"],
            intervention_instance_id=intervention_instance_id,
        )

        # Update intervention instance status
        if success:
            bq_client.update_intervention_instance_status(
                intervention_instance_id=intervention_instance_id,
                status="sent",
                sent_at=datetime.now(timezone.utc),
            )
            logger.info(f"Successfully sent intervention {intervention_instance_id} to user {user_id}")
        else:
            # APNs not configured or failed - keep as "created" for Phase 1 testing
            logger.info(
                f"Push notification not sent for intervention {intervention_instance_id} "
                "(APNs not configured or failed). Status remains 'created'. "
                "Use HTTP endpoint to fetch intervention details."
            )
    else:
        logger.info(
            f"No device token for user {user_id}. Intervention {intervention_instance_id} created. "
            "Status: 'created'. Use HTTP endpoint to fetch intervention details."
        )


@functions_framework.cloud_event
def intervention_selector(cloud_event: CloudEvent) -> None:
    """Cloud Function triggered by Pub/Sub message from state_estimates topic.

    Args:
        cloud_event: CloudEvent from Pub/Sub
    """
    try:
        # Extract message data from Pub/Sub CloudEvent
        message_data = cloud_event.get_data()
        if message_data:
            if isinstance(message_data, bytes):
                decoded_data = base64.b64decode(message_data).decode("utf-8")
                try:
                    payload = json.loads(decoded_data)
                    logger.info(f"Received Pub/Sub message: {payload}")
                except json.JSONDecodeError:
                    logger.warning(f"Received non-JSON Pub/Sub message: {decoded_data}")
                    return
            elif isinstance(message_data, dict):
                payload = message_data
                logger.info(f"Received Pub/Sub message: {payload}")
            else:
                logger.warning(f"Unexpected message data type: {type(message_data)}")
                return

            # Extract user_id and timestamp from payload
            user_id = payload.get("user_id")
            timestamp = payload.get("timestamp")

            if not user_id or not timestamp:
                logger.error(f"Missing user_id or timestamp in payload: {payload}")
                return

            # Process state estimate
            logger.info(f"Processing state estimate for user {user_id} at {timestamp}")
            process_state_estimate(user_id=user_id, timestamp=timestamp)

        else:
            logger.warning("Received empty Pub/Sub message")

    except Exception as e:
        logger.error(f"Error in intervention selector pipeline: {e}", exc_info=True)
        raise  # Re-raise to trigger Cloud Function retry mechanism


@functions_framework.http
def get_intervention(request) -> tuple[Dict[str, Any], int]:
    """HTTP endpoint to get intervention instance details.

    Args:
        request: Flask request object

    Returns:
        Tuple of (response dict, status code)
    """
    try:
        # Extract intervention_instance_id from URL path
        # Expected path: /interventions/{intervention_instance_id}
        path = request.path.rstrip("/")  # Remove trailing slash
        
        # Handle both /interventions/{id} and /{id} patterns
        if path.startswith("/interventions/"):
            intervention_instance_id = path.split("/interventions/", 1)[1].split("?")[0].split("/")[0]
        elif path.startswith("/"):
            # Allow root path for simpler routing
            intervention_instance_id = path.lstrip("/").split("?")[0].split("/")[0]
        else:
            return {"error": "Invalid path. Expected /interventions/{id}"}, 400

        if not intervention_instance_id:
            return {"error": "Missing intervention_instance_id"}, 400

        project_id = os.getenv("GCP_PROJECT_ID")
        if not project_id:
            return {"error": "GCP_PROJECT_ID not configured"}, 500

        dataset_id = os.getenv("BQ_DATASET_ID", "shift_data")
        bq_client = BigQueryClient(project_id=project_id, dataset_id=dataset_id)

        # Get intervention instance
        instance = bq_client.get_intervention_instance(intervention_instance_id)
        if not instance:
            return {"error": "Intervention instance not found"}, 404

        # Get intervention details from catalog
        intervention = get_intervention(instance["intervention_key"])
        if not intervention:
            return {"error": "Intervention not found in catalog"}, 500

        # Return combined response
        response = {
            "intervention_instance_id": instance["intervention_instance_id"],
            "user_id": instance["user_id"],
            "metric": instance["metric"],
            "level": instance["level"],
            "surface": instance["surface"],
            "intervention_key": instance["intervention_key"],
            "title": intervention["title"],
            "body": intervention["body"],
            "created_at": instance["created_at"].isoformat() if instance["created_at"] else None,
            "scheduled_at": instance["scheduled_at"].isoformat() if instance["scheduled_at"] else None,
            "sent_at": instance["sent_at"].isoformat() if instance["sent_at"] else None,
            "status": instance["status"],
        }

        return response, 200

    except Exception as e:
        logger.error(f"Error getting intervention instance: {e}", exc_info=True)
        return {"error": "Internal server error"}, 500

