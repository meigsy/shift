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

    def get_catalog_interventions(self, metric: str, level: str) -> list[dict]:
        """Get enabled interventions from catalog for a given metric and level.

        Args:
            metric: Metric name (e.g., "stress")
            level: Level (e.g., "high", "medium", "low")

        Returns:
            List of intervention dicts with catalog fields
        """
        query = f"""
            SELECT
                intervention_key,
                metric,
                level,
                target_level,
                nudge_type,
                persona,
                surface,
                title,
                body,
                enabled
            FROM `{self.project_id}.{self.dataset_id}.intervention_catalog`
            WHERE enabled = TRUE
            AND metric = @metric
            AND level = @level
            ORDER BY intervention_key
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("metric", "STRING", metric),
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
                    "target_level": row.target_level,
                    "nudge_type": row.nudge_type,
                    "persona": row.persona,
                    "surface": row.surface,
                    "title": row.title,
                    "body": row.body,
                    "enabled": row.enabled,
                })

            return interventions
        except Exception as e:
            logger.error(f"Error querying intervention catalog: {e}", exc_info=True)
            raise

    def get_catalog_intervention_by_key(self, intervention_key: str) -> Optional[dict]:
        """Get a single intervention from catalog by intervention_key.

        Args:
            intervention_key: Intervention key

        Returns:
            Dict with intervention catalog fields or None if not found
        """
        query = f"""
            SELECT
                intervention_key,
                metric,
                level,
                target_level,
                nudge_type,
                persona,
                surface,
                title,
                body,
                enabled
            FROM `{self.project_id}.{self.dataset_id}.intervention_catalog`
            WHERE intervention_key = @intervention_key
            LIMIT 1
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("intervention_key", "STRING", intervention_key),
            ]
        )

        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()

            for row in results:
                return {
                    "intervention_key": row.intervention_key,
                    "metric": row.metric,
                    "level": row.level,
                    "target_level": row.target_level,
                    "nudge_type": row.nudge_type,
                    "persona": row.persona,
                    "surface": row.surface,
                    "title": row.title,
                    "body": row.body,
                    "enabled": row.enabled,
                }

            return None
        except Exception as e:
            logger.error(f"Error querying intervention catalog by key: {e}", exc_info=True)
            raise

    def get_surface_preferences(self, user_id: str) -> dict[str, dict]:
        """Get surface preferences for a user.

        Args:
            user_id: User ID

        Returns:
            Dict keyed by surface name, containing preference stats:
            {
                "notification_banner": {
                    "preference_score": 0.5,
                    "annoyance_rate": 0.2,
                    "ignore_rate": 0.1,
                    "shown_count": 10,
                    ...
                },
                ...
            }
        """
        query = f"""
            SELECT
                surface,
                shown_count,
                preference_score,
                annoyance_rate,
                ignore_rate,
                engagement_rate
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
                    "preference_score": row.preference_score if row.preference_score is not None else 0.0,
                    "annoyance_rate": row.annoyance_rate if row.annoyance_rate is not None else 0.0,
                    "ignore_rate": row.ignore_rate if row.ignore_rate is not None else 0.0,
                    "shown_count": row.shown_count if row.shown_count is not None else 0,
                    "engagement_rate": row.engagement_rate if row.engagement_rate is not None else 0.0,
                }

            return preferences
        except Exception as e:
            # Graceful degradation: if view doesn't exist or query fails, return empty dict
            logger.warning(f"Error querying surface preferences (returning empty): {e}")
            return {}

    def has_completed_flow(self, user_id: str, flow_id: str, flow_version: str = "v1") -> bool:
        """Check if user has completed a specific flow version.
        
        Looks for latest flow_completed event for the flow_id/version, then checks
        if there's a later flow_reset event that would invalidate it.
        
        Args:
            user_id: User ID
            flow_id: Flow ID (e.g., "getting_started")
            flow_version: Flow version (e.g., "v1")
            
        Returns:
            True if flow is completed (not reset), False otherwise
        """
        query = f"""
            WITH cte_events AS (
                SELECT
                    event_type,
                    JSON_EXTRACT_SCALAR(payload, '$.flow_id') AS flow_id,
                    JSON_EXTRACT_SCALAR(payload, '$.flow_version') AS flow_version,
                    JSON_EXTRACT_SCALAR(payload, '$.scope') AS scope,
                    timestamp
                FROM `{self.project_id}.{self.dataset_id}.app_interactions`
                WHERE user_id = @user_id
                  AND event_type IN ('flow_completed', 'flow_reset')
                  AND (
                    JSON_EXTRACT_SCALAR(payload, '$.flow_id') = @flow_id
                    OR JSON_EXTRACT_SCALAR(payload, '$.scope') = 'all'
                    OR JSON_EXTRACT_SCALAR(payload, '$.scope') = 'flows'
                  )
                ORDER BY timestamp DESC
            )
            SELECT
                event_type,
                flow_id,
                flow_version,
                timestamp
            FROM cte_events
            LIMIT 1
        """
        
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
                bigquery.ScalarQueryParameter("flow_id", "STRING", flow_id),
            ]
        )
        
        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()
            
            for row in results:
                if row.event_type == "flow_completed":
                    # Check if flow_version matches
                    if row.flow_version == flow_version or (row.flow_version is None and flow_version == "v1"):
                        return True
                elif row.event_type == "flow_reset":
                    # Reset found - flow is not completed
                    return False
            
            return False
        except Exception as e:
            logger.error(f"Error checking flow completion: {e}", exc_info=True)
            return False

    def has_recent_flow_request(self, user_id: str, flow_id: str, minutes: int = 5) -> bool:
        """Check if user has requested a flow recently (e.g., via About SHIFT).
        
        Args:
            user_id: User ID
            flow_id: Flow ID (e.g., "getting_started")
            minutes: Time window in minutes (default 5)
            
        Returns:
            True if flow_requested event found in last N minutes
        """
        query = f"""
            SELECT
                COUNT(*) as count
            FROM `{self.project_id}.{self.dataset_id}.app_interactions`
            WHERE user_id = @user_id
              AND event_type = 'flow_requested'
              AND JSON_EXTRACT_SCALAR(payload, '$.flow_id') = @flow_id
              AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @minutes MINUTE)
        """
        
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
                bigquery.ScalarQueryParameter("flow_id", "STRING", flow_id),
                bigquery.ScalarQueryParameter("minutes", "INT64", minutes),
            ]
        )
        
        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()
            
            for row in results:
                return row.count > 0
            
            return False
        except Exception as e:
            logger.error(f"Error checking flow request: {e}", exc_info=True)
            return False

    def get_existing_getting_started_instance(self, user_id: str, intervention_key: str) -> Optional[str]:
        """Check if user already has an active getting_started intervention instance for a specific key.
        
        Checks for an existing instance with the same intervention_key and status='created'.
        This prevents duplicate instances of the same version before completion.
        
        Args:
            user_id: User ID
            intervention_key: Specific intervention key to check (e.g., "getting_started_v1")
            
        Returns:
            Intervention instance ID if exists, None otherwise
        """
        query = f"""
            SELECT
                intervention_instance_id
            FROM `{self.project_id}.{self.dataset_id}.intervention_instances`
            WHERE user_id = @user_id
              AND intervention_key = @intervention_key
              AND status = 'created'
            ORDER BY created_at DESC
            LIMIT 1
        """
        
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
                bigquery.ScalarQueryParameter("intervention_key", "STRING", intervention_key),
            ]
        )
        
        try:
            query_job = self.client.query(query, job_config=job_config)
            results = query_job.result()
            
            for row in results:
                return row.intervention_instance_id
            
            return None
        except Exception as e:
            logger.error(f"Error checking existing getting_started instance: {e}", exc_info=True)
            return None

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
            WHERE user_id = @user_id
            AND status = @status
            ORDER BY created_at DESC
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
                intervention = get_intervention(row.intervention_key, self)
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


