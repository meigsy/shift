"""Intervention selection logic."""

import logging
from typing import Optional

from src.bucketing import bucket_stress
from src.catalog import get_intervention

logger = logging.getLogger(__name__)


def select_intervention(stress: float | None) -> dict | None:
    """Select intervention based on stress level.

    Args:
        stress: Stress score (0-1) or None

    Returns:
        Intervention dict or None if no intervention should be sent
    """
    if stress is None:
        logger.info("Stress is None, skipping intervention selection")
        return None

    level = bucket_stress(stress)
    if level is None:
        logger.info("Could not bucket stress level, skipping intervention selection")
        return None

    # Select intervention based on metric and level
    intervention_key = f"stress_{level}_notification"
    intervention = get_intervention(intervention_key)

    if intervention is None:
        logger.warning(f"Intervention not found for key: {intervention_key}")
        return None

    logger.info(f"Selected intervention: {intervention_key} for stress level: {level}")
    return intervention



