"""Hard-coded intervention catalog for Phase 1."""

INTERVENTIONS = {
    "stress_high_notification": {
        "intervention_key": "stress_high_notification",
        "metric": "stress",
        "level": "high",
        "surface": "notification",
        "title": "Take a Short Reset",
        "body": "You seem overloaded. Take a 5-minute break.",
    },
    "stress_medium_notification": {
        "intervention_key": "stress_medium_notification",
        "metric": "stress",
        "level": "medium",
        "surface": "notification",
        "title": "Quick Check-in",
        "body": "How are you doing? Consider a breathing break.",
    },
    "stress_low_notification": {
        "intervention_key": "stress_low_notification",
        "metric": "stress",
        "level": "low",
        "surface": "notification",
        "title": "Nice Work",
        "body": "You're keeping stress low today. Keep it up!",
    },
}


def get_intervention(intervention_key: str) -> dict | None:
    """Get intervention by key.

    Args:
        intervention_key: Intervention key (e.g., "stress_high_notification")

    Returns:
        Intervention dict or None if not found
    """
    return INTERVENTIONS.get(intervention_key)





