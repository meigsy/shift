from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, timezone
from google.cloud import firestore
import logging
import json

logger = logging.getLogger(__name__)


class Profile(BaseModel):
    """User profile information"""
    name: Optional[str] = None
    age: Optional[int] = None
    experience_level: Optional[str] = None  # "beginner", "intermediate", "advanced"
    notification_preference: str = "balanced"  # "off", "minimal", "balanced", "proactive"
    quiet_hours: Optional[dict] = None  # {"start": "22:00", "end": "08:00"}


class Goals(BaseModel):
    """User's health and fitness goals - flexible structure"""
    long_term: List[str] = []  # Any long-term goals user mentions
    current_focus: Optional[str] = None  # What they're working on right now
    timeline: Optional[str] = None  # When they want to achieve goals
    priority: Optional[str] = None  # "high", "medium", "low" (agent decides)
    status: Optional[str] = None  # "active", "paused", "completed" (agent decides)
    notes: Optional[str] = None  # Additional context about goals


class Context(BaseModel):
    """Recent context from conversations"""
    last_checkin: Optional[datetime] = None
    last_grow_goal: Optional[str] = None  # Most recent G from GROW
    current_W: Optional[str] = None  # "What will you do next" from last GROW


class UserGoalsAndContext(BaseModel):
    """Complete user context - stored in Firestore with append-only versioning"""
    profile: Profile = Profile()
    goals: Goals = Goals()
    context: Context = Context()
    created_at: Optional[datetime] = None


def get_firestore_client(project_id: str) -> firestore.Client:
    """Get Firestore client."""
    return firestore.Client(project=project_id)


def get_user_context(user_id: str, project_id: str) -> UserGoalsAndContext:
    """
    Load latest user context from Firestore.
    Query: user_context/{user_id}/versions, order by created_at DESC, limit 1
    Returns default empty context if not found.
    """
    try:
        db = get_firestore_client(project_id)
        versions_ref = db.collection("user_context").document(user_id).collection("versions")
        
        # Get latest version
        query = versions_ref.order_by("created_at", direction=firestore.Query.DESCENDING).limit(1)
        docs = list(query.stream())
        
        if docs:
            data = docs[0].to_dict()
            logger.info(f"[get_user_context] Loaded context for user {user_id}")
            return UserGoalsAndContext(**data)
        else:
            logger.info(f"[get_user_context] No context found for user {user_id}, returning defaults")
            return UserGoalsAndContext()
    except Exception as e:
        logger.error(f"[get_user_context] Error loading context: {e}")
        return UserGoalsAndContext()


def save_user_context(user_id: str, project_id: str, context: UserGoalsAndContext):
    """
    Save user context to Firestore (append-only).
    Writes to: user_context/{user_id}/versions/{timestamp_id}
    """
    try:
        db = get_firestore_client(project_id)
        versions_ref = db.collection("user_context").document(user_id).collection("versions")
        
        # Set created_at timestamp
        context.created_at = datetime.now(timezone.utc)
        
        # Convert to dict (Pydantic handles datetime serialization)
        data = json.loads(context.model_dump_json())
        
        # Use timestamp as doc ID for append-only
        timestamp_id = context.created_at.strftime("%Y%m%d_%H%M%S_%f")
        versions_ref.document(timestamp_id).set(data)
        
        logger.info(f"[save_user_context] Saved context for user {user_id} (version: {timestamp_id})")
    except Exception as e:
        logger.error(f"[save_user_context] Error saving context: {e}")
        raise


def parse_and_update_context(
    update_description: str,
    current_context: UserGoalsAndContext
) -> UserGoalsAndContext:
    """
    Parse natural language update and merge into context.
    
    Phase 1: Simple keyword matching.
    Future: Use LLM to parse structured updates.
    """
    import re
    desc_lower = update_description.lower()
    
    # Profile updates
    if "name" in desc_lower:
        match = re.search(r"name is (\w+)", desc_lower)
        if match:
            current_context.profile.name = match.group(1).capitalize()
    
    if "age" in desc_lower:
        match = re.search(r"age (\d+)", desc_lower)
        if match:
            current_context.profile.age = int(match.group(1))
    
    if "experience" in desc_lower or "beginner" in desc_lower or "intermediate" in desc_lower or "advanced" in desc_lower:
        if "beginner" in desc_lower:
            current_context.profile.experience_level = "beginner"
        elif "intermediate" in desc_lower:
            current_context.profile.experience_level = "intermediate"
        elif "advanced" in desc_lower:
            current_context.profile.experience_level = "advanced"
    
    # Goals updates - agent decides how to structure via prompt
    # Just add to long_term if it looks like a goal
    goal_keywords = ["want", "goal", "body fat", "bf%", "ffmi", "muscle", "sleep", "surf", "workout"]
    if any(keyword in desc_lower for keyword in goal_keywords):
        # Add to long_term if not already present
        if update_description not in current_context.goals.long_term:
            current_context.goals.long_term.append(update_description)
    
    # Active focus updates
    if any(keyword in desc_lower for keyword in ["tomorrow", "today", "next", "upcoming", "preparing"]):
        current_context.goals.current_focus = update_description
    
    return current_context

