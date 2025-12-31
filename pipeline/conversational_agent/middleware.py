from langchain.agents.middleware import AgentMiddleware
import logging

logger = logging.getLogger(__name__)


class ContextInjectionMiddleware(AgentMiddleware):
    """
    Stub middleware for context injection.
    Phase 0: Just logs that it ran, passes through unchanged.
    Future: Will load user context from Firestore + BigQuery.
    """
    
    def before_model(self, request):
        """Called before each model invocation."""
        logger.info(f"[ContextInjectionMiddleware] before_model called for user")
        # Phase 0: Just pass through unchanged
        return request

