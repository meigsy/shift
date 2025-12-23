"""Pydantic models for request/response schemas."""

from pydantic import BaseModel


class ChatRequestBody(BaseModel):
    """Request body for /chat endpoint."""
    message: str
    thread_id: str | None = None


