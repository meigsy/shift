"""Bucketing logic for state metrics."""

# Bucketing thresholds (constants for Phase 1)
STRESS_HIGH_THRESHOLD = 0.7
STRESS_MEDIUM_THRESHOLD = 0.3


def bucket_stress(stress: float | None) -> str | None:
    """Bucket stress score into high, medium, or low.

    Args:
        stress: Stress score (0-1) or None

    Returns:
        "high", "medium", "low", or None if stress is None
    """
    if stress is None:
        return None

    if stress > STRESS_HIGH_THRESHOLD:
        return "high"
    elif stress >= STRESS_MEDIUM_THRESHOLD:
        return "medium"
    else:
        return "low"





