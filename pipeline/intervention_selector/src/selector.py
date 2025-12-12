"""Intervention selection logic with preference-based scoring."""

import logging
from typing import Optional, Dict, Any

from src.bucketing import bucket_stress
from src.catalog import get_interventions_for_state

logger = logging.getLogger(__name__)


def select_intervention(
    state_estimate: dict,
    bq_client,
    user_id: str,
) -> Optional[Dict[str, Any]]:
    """Select an intervention based on state estimate and user preferences.

    Args:
        state_estimate: Dict with state estimate data including:
            - stress: float (0-1) or None
            - Other metrics (fatigue, mood) - not used in MVP
        bq_client: BigQueryClient instance
        user_id: User ID for preference lookup

    Returns:
        Dict with intervention fields:
        - intervention_key
        - metric
        - level
        - surface
        - title
        - body
        - nudge_type
        Or None if no intervention should be selected
    """
    # MVP: Only handle stress metric
    metric = "stress"
    stress_score = state_estimate.get("stress")

    if stress_score is None:
        logger.info(f"No stress score in state estimate for user {user_id}")
        return None

    # Bucket stress score to level
    level = bucket_stress(stress_score)
    if level is None:
        logger.info(f"Could not bucket stress score {stress_score} for user {user_id}")
        return None

    logger.info(f"Selecting intervention for user {user_id}: metric={metric}, level={level}, stress_score={stress_score}")

    # Get candidate interventions from catalog
    candidates = get_interventions_for_state(bq_client, metric=metric, level=level)
    if not candidates:
        logger.warning(f"No interventions found in catalog for metric={metric}, level={level}")
        return None

    logger.info(f"Found {len(candidates)} candidate interventions")

    # Get surface preferences for user
    surface_prefs = bq_client.get_surface_preferences(user_id)
    if not surface_prefs:
        logger.info(f"No surface preferences found for user {user_id}, using default scoring")

    # Score and filter candidates
    scored_candidates = []
    for candidate in candidates:
        surface = candidate["surface"]
        surface_pref = surface_prefs.get(surface, {})

        # Extract preference stats
        preference_score = surface_pref.get("preference_score", 0.0)
        annoyance_rate = surface_pref.get("annoyance_rate", 0.0)
        shown_count = surface_pref.get("shown_count", 0)

        # Cap annoyance_rate to prevent 100% suppression (allow recovery over time)
        # Even if user has 100% dismissal rate, cap at 90% for suppression purposes
        # This ensures surfaces can recover as user preferences evolve
        annoyance_rate_capped = min(annoyance_rate, 0.9)

        # Suppression rule: if shown_count >= 5 AND capped annoyance_rate > 0.7, suppress
        if shown_count >= 5 and annoyance_rate_capped > 0.7:
            logger.info(f"Suppressing surface '{surface}' for user {user_id}: shown_count={shown_count}, annoyance_rate={annoyance_rate} (capped at {annoyance_rate_capped})")
            continue

        # Calculate final score
        base_score = 1.0
        final_score = base_score + preference_score

        scored_candidates.append({
            "candidate": candidate,
            "final_score": final_score,
            "surface": surface,
            "preference_score": preference_score,
        })

    if not scored_candidates:
        logger.warning(f"All candidates suppressed for user {user_id}, metric={metric}, level={level}")
        return None

    # Select candidate with highest final_score
    # Tie-break by lexicographic intervention_key (deterministic)
    scored_candidates.sort(key=lambda x: (-x["final_score"], x["candidate"]["intervention_key"]))
    selected = scored_candidates[0]

    logger.info(
        f"Selected intervention for user {user_id}: "
        f"key={selected['candidate']['intervention_key']}, "
        f"surface={selected['surface']}, "
        f"final_score={selected['final_score']:.3f} "
        f"(preference_score={selected['preference_score']:.3f})"
    )

    # Return dict matching what main.py expects
    return {
        "intervention_key": selected["candidate"]["intervention_key"],
        "metric": selected["candidate"]["metric"],
        "level": selected["candidate"]["level"],
        "surface": selected["candidate"]["surface"],
        "title": selected["candidate"]["title"],
        "body": selected["candidate"]["body"],
        "nudge_type": selected["candidate"]["nudge_type"],
    }
