from pydantic import BaseModel
from typing import Optional, Any


class ChatRequestBody(BaseModel):
    message: str
    thread_id: str | None = None


class ToolEventBody(BaseModel):
    """Schema for /tool_event endpoint"""
    type: str  # Event type: "app_opened", "card_tapped", "rating_submitted", etc.
    intervention_key: Optional[str] = None  # For card_tapped events
    suggested_action: Optional[str] = None  # For card_tapped events
    context: Optional[str] = None  # Additional context about the event
    value: Optional[Any] = None  # For ratings, metric values
    timestamp: str  # ISO format timestamp
    thread_id: Optional[str] = None  # Optional thread to continue
