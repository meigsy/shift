"""Catalog access for intervention selector."""

import logging
from typing import List, Dict, Any, Optional

logger = logging.getLogger(__name__)


def get_interventions_for_state(
    bq_client,
    metric: str,
    level: str,
) -> List[Dict[str, Any]]:
    """Get enabled interventions from catalog for a given metric and level.

    Args:
        bq_client: BigQueryClient instance
        metric: Metric name (e.g., "stress")
        level: Level (e.g., "high", "medium", "low")

    Returns:
        List of intervention dicts with catalog fields:
        - intervention_key
        - metric
        - level
        - target_level
        - nudge_type
        - persona
        - surface
        - title
        - body
        - enabled
    """
    try:
        return bq_client.get_catalog_interventions(metric=metric, level=level)
    except Exception as e:
        logger.error(f"Error fetching interventions for state (metric={metric}, level={level}): {e}", exc_info=True)
        return []


def get_intervention(intervention_key: str, bq_client) -> Optional[Dict[str, Any]]:
    """Get a single intervention from catalog by intervention_key.

    Args:
        intervention_key: Intervention key
        bq_client: BigQueryClient instance

    Returns:
        Dict with intervention catalog fields or None if not found
    """
    try:
        return bq_client.get_catalog_intervention_by_key(intervention_key)
    except Exception as e:
        logger.error(f"Error fetching intervention by key ({intervention_key}): {e}", exc_info=True)
        return None
