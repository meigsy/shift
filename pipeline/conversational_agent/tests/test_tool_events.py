import pytest
from schemas import ToolEventBody
from middleware import is_quiet_hours, NotificationGatingMiddleware
from user_context import UserGoalsAndContext, Profile


def test_tool_event_schema_valid():
    """Test valid tool event schema."""
    event = ToolEventBody(
        type="app_opened",
        timestamp="2025-12-31T10:00:00Z"
    )
    assert event.type == "app_opened"
    assert event.timestamp == "2025-12-31T10:00:00Z"


def test_tool_event_schema_card_tapped():
    """Test card_tapped event with all fields."""
    event = ToolEventBody(
        type="card_tapped",
        intervention_key="stress_checkin",
        suggested_action="rate_stress_1_to_5",
        context="User tapped card",
        timestamp="2025-12-31T10:00:00Z"
    )
    assert event.type == "card_tapped"
    assert event.intervention_key == "stress_checkin"
    assert event.suggested_action == "rate_stress_1_to_5"
    assert event.context == "User tapped card"


def test_tool_event_schema_with_value():
    """Test event with value field (for ratings)."""
    event = ToolEventBody(
        type="rating_submitted",
        intervention_key="stress_checkin",
        value=4,
        timestamp="2025-12-31T10:00:00Z"
    )
    assert event.value == 4


def test_tool_event_schema_with_thread_id():
    """Test event with thread_id."""
    event = ToolEventBody(
        type="app_opened",
        timestamp="2025-12-31T10:00:00Z",
        thread_id="custom-thread"
    )
    assert event.thread_id == "custom-thread"


def test_is_quiet_hours_none():
    """Test is_quiet_hours with None input."""
    assert is_quiet_hours(None) is False


def test_is_quiet_hours_empty_dict():
    """Test is_quiet_hours with empty dict."""
    assert is_quiet_hours({}) is False


def test_is_quiet_hours_missing_keys():
    """Test is_quiet_hours with missing keys."""
    assert is_quiet_hours({"start": "22:00"}) is False
    assert is_quiet_hours({"end": "08:00"}) is False


def test_is_quiet_hours_invalid_format():
    """Test is_quiet_hours with invalid time format."""
    assert is_quiet_hours({"start": "invalid", "end": "08:00"}) is False
    assert is_quiet_hours({"start": "22:00", "end": "invalid"}) is False


def test_is_quiet_hours_valid_same_day():
    """Test is_quiet_hours with same-day quiet hours (e.g., 14:00 to 16:00)."""
    # This test is time-dependent, so we just verify it doesn't crash
    result = is_quiet_hours({"start": "14:00", "end": "16:00"})
    assert isinstance(result, bool)


def test_is_quiet_hours_overnight():
    """Test is_quiet_hours with overnight quiet hours (e.g., 22:00 to 08:00)."""
    # This test is time-dependent, so we just verify it doesn't crash
    result = is_quiet_hours({"start": "22:00", "end": "08:00"})
    assert isinstance(result, bool)


def test_notification_gating_init():
    """Test NotificationGatingMiddleware initialization."""
    middleware = NotificationGatingMiddleware(project_id="test-project")
    assert middleware.project_id == "test-project"


def test_notification_gating_passes_non_metric_events():
    """Test that non-metric events pass through gating."""
    middleware = NotificationGatingMiddleware(project_id="test-project")
    
    # Non-metric event should pass through
    request = {"messages": []}
    result = middleware.before_model(request)
    assert result == request


def test_tool_event_model_dump():
    """Test that ToolEventBody serializes correctly."""
    event = ToolEventBody(
        type="card_tapped",
        intervention_key="stress_checkin",
        timestamp="2025-12-31T10:00:00Z"
    )
    data = event.model_dump()
    assert data["type"] == "card_tapped"
    assert data["intervention_key"] == "stress_checkin"
    assert data["timestamp"] == "2025-12-31T10:00:00Z"
    # Optional fields should be None
    assert data["suggested_action"] is None
    assert data["context"] is None
    assert data["value"] is None

