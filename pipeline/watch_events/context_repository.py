"""Read-only BigQuery access for the /context endpoint."""

from datetime import datetime
from typing import Any, Dict, List, Optional

import os

from google.cloud import bigquery


class ContextRepository:
    """Repository for fetching state and interventions for the context payload.

    This is READ-ONLY. It must not create or mutate any rows.
    """

    def __init__(self, project_id: str, dataset_id: str = "shift_data") -> None:
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.client = bigquery.Client(project=project_id)

    def get_latest_state_estimate(self, user_id: str) -> Optional[Dict[str, Any]]:
        """Fetch the latest state_estimates row for a user."""
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

    def get_created_interventions_for_user(self, user_id: str) -> List[Dict[str, Any]]:
        """Fetch all intervention_instances with status='created' for a user."""
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
              AND status = 'created'
            ORDER BY created_at DESC
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
            ]
        )

        query_job = self.client.query(query, job_config=job_config)
        results = query_job.result()

        interventions: List[Dict[str, Any]] = []
        for row in results:
            interventions.append(
                {
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
            )

        return interventions

    def get_catalog_for_keys(self, keys: List[str]) -> Dict[str, Dict[str, Any]]:
        """Fetch intervention_catalog rows for the given intervention keys.

        Returns a mapping of intervention_key -> catalog row.
        """
        if not keys:
            return {}

        table = f"{self.project_id}.{self.dataset_id}.intervention_catalog"

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
            FROM `{table}`
            WHERE intervention_key IN UNNEST(@keys)
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ArrayQueryParameter("keys", "STRING", keys),
            ]
        )

        query_job = self.client.query(query, job_config=job_config)
        results = query_job.result()

        catalog_by_key: Dict[str, Dict[str, Any]] = {}
        for row in results:
            catalog_by_key[row.intervention_key] = {
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

        return catalog_by_key

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





