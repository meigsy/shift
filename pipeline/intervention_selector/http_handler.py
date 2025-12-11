"""HTTP handler for intervention selector (separate Cloud Function)."""

import logging
import os
from typing import Dict, Any

import functions_framework

from src.bigquery_client import BigQueryClient
from src.catalog import get_intervention

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


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
        intervention = get_intervention(instance["intervention_key"], bq_client)
        if not intervention:
            return {"error": "Intervention not found in catalog"}, 500

        # Return combined response
        # CRITICAL: trace_id is REQUIRED for 100% traceability
        trace_id = instance.get("trace_id")
        if not trace_id:
            from uuid import uuid4
            trace_id = str(uuid4())
            logger.error(f"⚠️ CRITICAL: Missing trace_id in intervention {instance['intervention_instance_id']}! Generated: {trace_id}")
        
        response = {
            "intervention_instance_id": instance["intervention_instance_id"],
            "user_id": instance["user_id"],
            "trace_id": trace_id,  # REQUIRED - always included
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

