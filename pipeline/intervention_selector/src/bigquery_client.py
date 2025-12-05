"""BigQuery client for reading state estimates and writing intervention instances."""

import logging
import os
from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4

from google.cloud import bigquery

logger = logging.getLogger(__name__)


class BigQueryClient:
    """BigQuery client for intervention selector operations."""

    def __init__(self, project_id: str, dataset_id: str = "shift_data"):
        """Initialize BigQuery client.

        Args:
            project_id: GCP project ID
            dataset_id: BigQuery dataset ID (default: shift_data)
        """
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.client = bigquery.Client(project=project_id)

    def get_latest_state_estimate(self, user_id: str) -> Optional[dict]:
        """Get the latest state estimate for a user.

        Args:
            user_id: User ID

        Returns:
            Dict with state estimate data or None if not found
        """
        query = f"""
            SELECT
                user_id,
                timestamp,
                trace_id,
                recovery,
                readiness,
                stress,
                fatigue
            FROM `{self.project_id}.{self.dataset_id}.state_estimates`
            WHERE user_id = @user_id
            ORDER BY timestamp DESC
            LIMIT 1
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()

            for row in results:
                return {
                    "user_id": row.user_id,
                    "timestamp": row.timestamp,
                    "trace_id": row.trace_id,
                    "recovery": row.recovery,
                    "readiness": row.readiness,
                    "stress": row.stress,
                    "fatigue": row.fatigue,
                }

            return None
        except Exception as e:
            logger.error(f"Error querying state estimates: {e}", exc_info=True)
            raise

    def create_intervention_instance(
        self,
        user_id: str,
        metric: str,
        level: str,
        surface: str,
        intervention_key: str,
        trace_id: str,  # REQUIRED - no longer optional
    ) -> str:
        """Create an intervention instance record in BigQuery.

        Args:
            user_id: User ID
            metric: Metric name (e.g., "stress")
            level: Level (e.g., "high")
            surface: Surface (e.g., "notification")
            intervention_key: Intervention key

        Returns:
            Intervention instance ID (UUID)
        """
        intervention_instance_id = str(uuid4())
        now = datetime.now(timezone.utc)

        rows_to_insert = [
            {
                "intervention_instance_id": intervention_instance_id,
                "user_id": user_id,
                "trace_id": trace_id,
                "metric": metric,
                "level": level,
                "surface": surface,
                "intervention_key": intervention_key,
                "created_at": now.isoformat(),
                "scheduled_at": now.isoformat(),
                "sent_at": None,
                "status": "created",
            }
        ]

        table_id = f"{self.project_id}.{self.dataset_id}.intervention_instances"

        try:
            errors = self.client.insert_rows_json(table_id, rows_to_insert)
            if errors:
                logger.error(f"Error inserting intervention instance: {errors}")
                raise RuntimeError(f"Failed to insert intervention instance: {errors}")

            logger.info(f"Created intervention instance: {intervention_instance_id}")
            return intervention_instance_id
        except Exception as e:
            logger.error(f"Error creating intervention instance: {e}", exc_info=True)
            raise

    def record_intervention_status_change(
        self,
        intervention_instance_id: str,
        trace_id: str,
        user_id: str,
        status: str,
        sent_at: Optional[datetime] = None,
    ) -> None:
        """Record intervention status change (append-only for 100% traceability).

        Args:
            intervention_instance_id: Intervention instance ID
            trace_id: Trace ID for full traceability
            user_id: User ID
            status: New status ("sent", "dismissed", or "failed")
            sent_at: Timestamp when sent (optional)
        
        Note: This is append-only - we never UPDATE existing rows. All status changes
        are recorded as new rows in intervention_status_changes table.
        """
        from uuid import uuid4
        
        table_id = f"{self.project_id}.{self.dataset_id}.intervention_status_changes"
        status_change_id = str(uuid4())
        changed_at = datetime.now(timezone.utc)

        rows_to_insert = [
            {
                "status_change_id": status_change_id,
                "intervention_instance_id": intervention_instance_id,
                "trace_id": trace_id,
                "user_id": user_id,
                "status": status,
                "sent_at": sent_at.isoformat() if sent_at else None,
                "changed_at": changed_at.isoformat(),
            }
        ]

        try:
            errors = self.client.insert_rows_json(table_id, rows_to_insert)
            if errors:
                logger.error(f"Error inserting status change: {errors}")
                raise RuntimeError(f"Failed to insert status change: {errors}")

            logger.info(
                f"Recorded status change for intervention {intervention_instance_id}: "
                f"{status} (change_id: {status_change_id})"
            )
        except Exception as e:
            logger.error(f"Error recording intervention status change: {e}", exc_info=True)
            raise

    def get_intervention_instance(self, intervention_instance_id: str) -> Optional[dict]:
        """Get intervention instance by ID with latest status from status_changes table.

        Args:
            intervention_instance_id: Intervention instance ID

        Returns:
            Dict with intervention instance data (including latest status) or None if not found
        """
        query = f"""
            WITH latest_status AS (
                SELECT
                    intervention_instance_id,
                    status,
                    sent_at,
                    ROW_NUMBER() OVER (PARTITION BY intervention_instance_id ORDER BY changed_at DESC) as rn
                FROM `{self.project_id}.{self.dataset_id}.intervention_status_changes`
                WHERE intervention_instance_id = @intervention_instance_id
            )
            SELECT
                i.intervention_instance_id,
                i.user_id,
                i.trace_id,
                i.metric,
                i.level,
                i.surface,
                i.intervention_key,
                i.created_at,
                i.scheduled_at,
                COALESCE(ls.sent_at, i.sent_at) as sent_at,
                COALESCE(ls.status, i.status) as status
            FROM `{self.project_id}.{self.dataset_id}.intervention_instances` i
            LEFT JOIN latest_status ls ON i.intervention_instance_id = ls.intervention_instance_id AND ls.rn = 1
            WHERE i.intervention_instance_id = @intervention_instance_id
            LIMIT 1
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("intervention_instance_id", "STRING", intervention_instance_id),
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()

            for row in results:
                return {
                    "intervention_instance_id": row.intervention_instance_id,
                    "user_id": row.user_id,
                    "trace_id": row.trace_id,
                    "metric": row.metric,
                    "level": row.level,
                    "surface": row.surface,
                    "intervention_key": row.intervention_key,
                    "created_at": row.created_at,
                    "scheduled_at": row.scheduled_at,
                    "sent_at": row.sent_at,
                    "status": row.status,
                }

            return None
        except Exception as e:
            logger.error(f"Error querying intervention instance: {e}", exc_info=True)
            raise

    def get_device_token(self, user_id: str) -> Optional[str]:
        """Get device token for a user.

        Args:
            user_id: User ID

        Returns:
            Device token or None if not found
        """
        query = f"""
            SELECT device_token
            FROM `{self.project_id}.{self.dataset_id}.devices`
            WHERE user_id = @user_id
            ORDER BY updated_at DESC
            LIMIT 1
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()

            for row in results:
                return row.device_token

            return None
        except Exception as e:
            logger.error(f"Error querying device token: {e}", exc_info=True)
            raise

    def get_interventions_for_user(
        self, user_id: str, status: str = "created"
    ) -> list[dict]:
        """Get interventions for a user filtered by status.

        Args:
            user_id: User ID
            status: Status filter (default: "created" for pending interventions)

        Returns:
            List of intervention instance dicts with catalog details merged
        """
        from src.catalog import get_intervention

        query = f"""
            WITH latest_status AS (
                SELECT
                    intervention_instance_id,
                    status,
                    sent_at,
                    ROW_NUMBER() OVER (PARTITION BY intervention_instance_id ORDER BY changed_at DESC) as rn
                FROM `{self.project_id}.{self.dataset_id}.intervention_status_changes`
            )
            SELECT
                i.intervention_instance_id,
                i.user_id,
                i.trace_id,
                i.metric,
                i.level,
                i.surface,
                i.intervention_key,
                i.created_at,
                i.scheduled_at,
                COALESCE(ls.sent_at, i.sent_at) as sent_at,
                COALESCE(ls.status, i.status) as status
            FROM `{self.project_id}.{self.dataset_id}.intervention_instances` i
            LEFT JOIN latest_status ls ON i.intervention_instance_id = ls.intervention_instance_id AND ls.rn = 1
            WHERE i.user_id = @user_id
            AND COALESCE(ls.status, i.status) = @status
            ORDER BY i.created_at DESC
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
                bigquery.ScalarQueryParameter("status", "STRING", status),
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()

            interventions = []
            for row in results:
                # Get intervention details from catalog
                intervention = get_intervention(row.intervention_key)
                if not intervention:
                    logger.warning(f"Intervention not found in catalog: {row.intervention_key}")
                    continue

                # Merge instance data with catalog details
                # CRITICAL: trace_id is REQUIRED for 100% traceability
                trace_id = row.trace_id
                if not trace_id:
                    trace_id = str(uuid4())
                    logger.error(f"⚠️ CRITICAL: Missing trace_id in intervention {row.intervention_instance_id}! Generated: {trace_id}")
                
                intervention_dict = {
                    "intervention_instance_id": row.intervention_instance_id,
                    "user_id": row.user_id,
                    "trace_id": trace_id,  # REQUIRED - always included
                    "metric": row.metric,
                    "level": row.level,
                    "surface": row.surface,
                    "intervention_key": row.intervention_key,
                    "title": intervention["title"],
                    "body": intervention["body"],
                    "created_at": row.created_at.isoformat() if row.created_at else None,
                    "scheduled_at": row.scheduled_at.isoformat() if row.scheduled_at else None,
                    "sent_at": row.sent_at.isoformat() if row.sent_at else None,
                    "status": row.status,
                }
                interventions.append(intervention_dict)

            return interventions
        except Exception as e:
            logger.error(f"Error querying interventions for user: {e}", exc_info=True)
            raise


