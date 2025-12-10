"""Intervention selection logic."""

import logging
from typing import Optional

from src.bucketing import bucket_stress
from src.bigquery_client import BigQueryClient

logger = logging.getLogger(__name__)


def select_intervention(
    state: dict,
    bq_client: BigQueryClient,
) -> dict | None:
    """Select intervention based on stress level, catalog, and user preferences.

    Args:
        state: State dict containing at least:
            - user_id: User ID
            - stress: Stress score (0-1) or None
            - trace_id: Trace ID (optional but recommended)
        bq_client: BigQuery client instance

    Returns:
        Intervention dict with:
            - intervention_key
            - surface
            - title
            - body
        Or None if no intervention should be sent
    """
    user_id = state.get("user_id")
    stress = state.get("stress")

    if user_id is None:
        logger.error("user_id is required in state dict")
        return None

    if stress is None:
        logger.info(f"Stress is None for user {user_id}, skipping intervention selection")
        return None

    # Bucket stress level
    level = bucket_stress(stress)
    if level is None:
        logger.info(f"Could not bucket stress level {stress} for user {user_id}, skipping intervention selection")
        return None

    # Get candidate interventions from catalog
    candidates = bq_client.get_catalog_for_stress_level(level)
    if not candidates:
        logger.info(f"No enabled interventions found for stress level {level} for user {user_id}")
        return None

    # Get user's surface preferences
    surface_prefs = bq_client.get_surface_preferences(user_id)

    # Score and filter candidates
    scored_candidates = []
    for candidate in candidates:
        surface = candidate["surface"]
        prefs = surface_prefs.get(surface, {})

        preference_score = prefs.get("preference_score", 0.0)
        annoyance_rate = prefs.get("annoyance_rate", 0.0)
        shown_count = prefs.get("shown_count", 0)

        # Compute final score with suppression logic
        if shown_count >= 5 and annoyance_rate > 0.7:
            final_score = -1.0  # Suppress this surface
            logger.info(
                f"Suppressing surface {surface} for user {user_id}: "
                f"shown_count={shown_count}, annoyance_rate={annoyance_rate:.2f}"
            )
        else:
            final_score = preference_score

        scored_candidates.append({
            "candidate": candidate,
            "final_score": final_score,
        })

    # Filter out suppressed candidates (final_score < 0)
    valid_candidates = [sc for sc in scored_candidates if sc["final_score"] >= 0]

    if not valid_candidates:
        logger.info(
            f"No valid interventions after preference filtering for user {user_id} "
            f"(all {len(candidates)} candidates suppressed)"
        )
        return None

    # Select candidate with highest final_score
    # If tie, pick first one
    best = max(valid_candidates, key=lambda sc: sc["final_score"])
    selected = best["candidate"]

    logger.info(
        f"Selected intervention {selected['intervention_key']} for user {user_id}: "
        f"stress_level={level}, surface={selected['surface']}, "
        f"final_score={best['final_score']:.2f}"
    )

    return selected






