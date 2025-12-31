from langchain.agents.middleware import AgentMiddleware
from langchain_core.messages import HumanMessage
import logging
from datetime import datetime, timezone
from user_context import get_user_context

logger = logging.getLogger(__name__)

# Phase 1 workaround: module-level user_id (set before agent invocation)
_current_user_id = None


def set_middleware_user_id(user_id: str):
    """Set user_id for middleware context injection (Phase 1 workaround)."""
    global _current_user_id
    _current_user_id = user_id


def is_quiet_hours(quiet_hours: dict | None) -> bool:
    """
    Check if current time is in user's quiet hours.
    
    Args:
        quiet_hours: dict with "start" and "end" times in HH:MM format
                    e.g. {"start": "22:00", "end": "08:00"}
    
    Returns:
        True if current time is in quiet hours
    """
    if not quiet_hours:
        return False
    
    try:
        start_str = quiet_hours.get("start")
        end_str = quiet_hours.get("end")
        if not start_str or not end_str:
            return False
        
        now = datetime.now(timezone.utc)
        current_time = now.hour * 60 + now.minute  # minutes since midnight
        
        start_parts = start_str.split(":")
        end_parts = end_str.split(":")
        start_minutes = int(start_parts[0]) * 60 + int(start_parts[1])
        end_minutes = int(end_parts[0]) * 60 + int(end_parts[1])
        
        # Handle overnight quiet hours (e.g., 22:00 to 08:00)
        if start_minutes > end_minutes:
            # Quiet hours span midnight
            return current_time >= start_minutes or current_time < end_minutes
        else:
            # Same-day quiet hours
            return start_minutes <= current_time < end_minutes
    except (ValueError, TypeError, AttributeError) as e:
        logger.warning(f"[is_quiet_hours] Error parsing quiet hours: {e}")
        return False


def recently_notified(user_id: str, project_id: str, within_hours: int = 4) -> bool:
    """
    Check if notification was sent recently.
    
    Phase 2 stub: Returns False (BigQuery integration in Phase 4)
    """
    # TODO: Query BigQuery app_interactions for recent send_notification events
    return False


class NotificationGatingMiddleware(AgentMiddleware):
    """
    Deterministic filtering for health_metric_changed events.
    Short-circuits agent invocation if gates fail.
    """
    
    def __init__(self, project_id: str):
        self.project_id = project_id
    
    def before_model(self, request):
        """
        Check notification gates before model invocation.
        Returns None to short-circuit if gates fail.
        """
        user_id = _current_user_id
        if not user_id:
            return request
        
        # Check if this is a health_metric_changed event (from ToolMessage)
        messages = request.get("messages", [])
        is_metric_event = False
        
        for msg in messages:
            if hasattr(msg, "type") and msg.type == "tool":
                try:
                    import json
                    content = json.loads(msg.content) if isinstance(msg.content, str) else msg.content
                    if content.get("type") == "health_metric_changed":
                        is_metric_event = True
                        break
                except (json.JSONDecodeError, TypeError):
                    pass
        
        # Only gate health_metric_changed events
        if not is_metric_event:
            return request
        
        logger.info(f"[NotificationGatingMiddleware] Checking gates for health_metric_changed event")
        
        # Load user preferences
        user_context = get_user_context(user_id, self.project_id)
        
        # Gate 1: Check notification preference
        if user_context.profile.notification_preference == "off":
            logger.info(f"[NotificationGatingMiddleware] Blocked: notifications off for user {user_id}")
            return None
        
        # Gate 2: Check quiet hours
        if is_quiet_hours(user_context.profile.quiet_hours):
            logger.info(f"[NotificationGatingMiddleware] Blocked: quiet hours for user {user_id}")
            return None
        
        # Gate 3: Check if recently notified
        if recently_notified(user_id, self.project_id, within_hours=4):
            logger.info(f"[NotificationGatingMiddleware] Blocked: recently notified user {user_id}")
            return None
        
        logger.info(f"[NotificationGatingMiddleware] All gates passed for user {user_id}")
        return request


class ContextInjectionMiddleware(AgentMiddleware):
    """
    Load user context from Firestore and inject into system prompt.
    """
    
    def __init__(self, project_id: str):
        self.project_id = project_id
    
    def before_model(self, request):
        """Load context and inject into system prompt before each model call."""
        # Phase 1: Get user_id from module-level variable (workaround)
        user_id = _current_user_id
        
        if not user_id:
            logger.warning("[ContextInjectionMiddleware] No user_id available")
            return request
        
        logger.info(f"[ContextInjectionMiddleware] Loading context for user {user_id}")
        
        # Load user context from Firestore
        user_context = get_user_context(user_id, self.project_id)
        
        # Format context for injection
        context_str = f"""[USER CONTEXT - Use this information about the user]

Profile:
- Name: {user_context.profile.name or "Unknown"}
- Age: {user_context.profile.age or "Unknown"}
- Experience: {user_context.profile.experience_level or "Not specified"}
- Notification Preference: {user_context.profile.notification_preference}

Goals:
- Long-term: {', '.join(user_context.goals.long_term) if user_context.goals.long_term else "None set"}
- Current Focus: {user_context.goals.current_focus or "None"}

[END USER CONTEXT]"""
        
        # Inject context by modifying the first human message
        messages = list(request.get("messages", []))
        
        # Find first human message and prepend context
        for i, msg in enumerate(messages):
            if hasattr(msg, "type") and msg.type == "human":
                # Check if context already injected
                if "[USER CONTEXT" not in (msg.content or ""):
                    # Prepend context to user message
                    modified_content = f"{context_str}\n\n---\nUser message: {msg.content}"
                    messages[i] = HumanMessage(content=modified_content, id=msg.id)
                    request["messages"] = messages
                    logger.info(f"[ContextInjectionMiddleware] Injected context for user {user_id}")
                break
        
        return request
