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

    def update_intervention_instance_status(
        self,
        intervention_instance_id: str,
        status: str,
        sent_at: Optional[datetime] = None,
    ) -> None:
        """Update intervention instance status.

        Args:
            intervention_instance_id: Intervention instance ID
            status: New status ("sent" or "failed")
            sent_at: Timestamp when sent (optional)
        """
        table_id = f"{self.project_id}.{self.dataset_id}.intervention_instances"

        # Build update query
        updates = [f"status = @status"]
        params = [
            bigquery.ScalarQueryParameter("intervention_instance_id", "STRING", intervention_instance_id),
            bigquery.ScalarQueryParameter("status", "STRING", status),
        ]

        if sent_at:
            updates.append("sent_at = @sent_at")
            params.append(bigquery.ScalarQueryParameter("sent_at", "TIMESTAMP", sent_at))

        query = f"""
            UPDATE `{table_id}`
            SET {', '.join(updates)}
            WHERE intervention_instance_id = @intervention_instance_id
        """

        job_config = bigquery.QueryJobConfig(query_parameters=params)

        try:
            query_job = self.client.query(query, job_config=job_config)
            query_job.result()  # Wait for completion
            logger.info(f"Updated intervention instance {intervention_instance_id} to status: {status}")
        except Exception as e:
            logger.error(f"Error updating intervention instance status: {e}", exc_info=True)
            raise

    def get_intervention_instance(self, intervention_instance_id: str) -> Optional[dict]:
        """Get intervention instance by ID.

        Args:
            intervention_instance_id: Intervention instance ID

        Returns:
            Dict with intervention instance data or None if not found
        """
        query = f"""
            SELECT
                intervention_instance_id,
                user_id,
                trace_id,
                metric,
                level,
                surface,
                intervention_key,
                created_at,
                scheduled_at,
                sent_at,
                status
            FROM `{self.project_id}.{self.dataset_id}.intervention_instances`
            WHERE intervention_instance_id = @intervention_instance_id
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
        query = f"""
            SELECT
                ii.intervention_instance_id,
                ii.user_id,
                ii.trace_id,
                ii.metric,
                ii.level,
                ii.surface,
                ii.intervention_key,
                ii.created_at,
                ii.scheduled_at,
                ii.sent_at,
                ii.status,
                ic.title,
                ic.body
            FROM `{self.project_id}.{self.dataset_id}.intervention_instances` ii
            LEFT JOIN `{self.project_id}.{self.dataset_id}.intervention_catalog` ic
              ON ii.intervention_key = ic.intervention_key
            WHERE ii.user_id = @user_id
              AND ii.status = @status
            ORDER BY ii.created_at DESC
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
                # CRITICAL: trace_id is REQUIRED for 100% traceability
                trace_id = row.trace_id
                if not trace_id:
                    trace_id = str(uuid4())
                    logger.error(f"⚠️ CRITICAL: Missing trace_id in intervention {row.intervention_instance_id}! Generated: {trace_id}")

                # Skip if catalog entry not found
                if not row.title or not row.body:
                    logger.warning(f"Intervention catalog entry not found for key: {row.intervention_key}")
                    continue
                
                intervention_dict = {
                    "intervention_instance_id": row.intervention_instance_id,
                    "user_id": row.user_id,
                    "trace_id": trace_id,  # REQUIRED - always included
                    "metric": row.metric,
                    "level": row.level,
                    "surface": row.surface,
                    "intervention_key": row.intervention_key,
                    "title": row.title,
                    "body": row.body,
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

    def get_surface_preferences(self, user_id: str) -> dict[str, dict]:
        """Get surface preferences for a user.

        Args:
            user_id: User ID

        Returns:
            Dict keyed by surface, each value containing:
                - preference_score
                - annoyance_rate
                - ignore_rate
                - shown_count
            Returns empty dict if no preferences found.
        """
        query = f"""
            SELECT
                surface,
                preference_score,
                annoyance_rate,
                ignore_rate,
                shown_count
            FROM `{self.project_id}.{self.dataset_id}.surface_preferences`
            WHERE user_id = @user_id
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()

            preferences = {}
            for row in results:
                preferences[row.surface] = {
                    "preference_score": float(row.preference_score) if row.preference_score is not None else 0.0,
                    "annoyance_rate": float(row.annoyance_rate) if row.annoyance_rate is not None else 0.0,
                    "ignore_rate": float(row.ignore_rate) if row.ignore_rate is not None else 0.0,
                    "shown_count": int(row.shown_count) if row.shown_count is not None else 0,
                }

            return preferences
        except Exception as e:
            logger.error(f"Error querying surface preferences: {e}", exc_info=True)
            raise

    def get_catalog_for_stress_level(self, level: str) -> list[dict]:
        """Get enabled interventions from catalog for a stress level.

        Args:
            level: Stress level ("high", "medium", "low")

        Returns:
            List of intervention dicts with:
                - intervention_key
                - surface
                - title
                - body
                - metric
                - level
        """
        query = f"""
            SELECT
                intervention_key,
                metric,
                level,
                surface,
                title,
                body
            FROM `{self.project_id}.{self.dataset_id}.intervention_catalog`
            WHERE metric = 'stress'
              AND level = @level
              AND enabled = TRUE
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("level", "STRING", level),
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()

            interventions = []
            for row in results:
                interventions.append({
                    "intervention_key": row.intervention_key,
                    "metric": row.metric,
                    "level": row.level,
                    "surface": row.surface,
                    "title": row.title,
                    "body": row.body,
                })

            return interventions
        except Exception as e:
            logger.error(f"Error querying intervention catalog: {e}", exc_info=True)
            raise

    def get_recent_intervention_count(self, user_id: str, minutes: int = 30) -> int:
        """Get count of interventions created for a user in the last N minutes.

        Args:
            user_id: User ID
            minutes: Number of minutes to look back (default: 30)

        Returns:
            Count of interventions created in the time window
        """
        query = f"""
            SELECT COUNT(*) as count
            FROM `{self.project_id}.{self.dataset_id}.intervention_instances`
            WHERE user_id = @user_id
              AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @minutes MINUTE)
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
                bigquery.ScalarQueryParameter("minutes", "INT64", minutes),
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()

            for row in results:
                return int(row.count)

            return 0
        except Exception as e:
            logger.error(f"Error querying recent intervention count: {e}", exc_info=True)
            raise


