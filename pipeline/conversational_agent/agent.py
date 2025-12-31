from langchain.agents import create_agent
from langchain.tools import tool
from langchain_anthropic import ChatAnthropic
from langgraph_checkpoint_firestore import FirestoreSaver
import logging

from middleware import ContextInjectionMiddleware, NotificationGatingMiddleware, set_middleware_user_id
from user_context import (
    get_user_context,
    save_user_context,
    parse_and_update_context
)

logger = logging.getLogger(__name__)

# Global to store project_id (set during agent creation)
_project_id = None


def set_project_id(project_id: str):
    """Set global project_id for tools to use."""
    global _project_id
    _project_id = project_id


@tool
def update_user_context(update_description: str) -> str:
    """
    Update user profile, goals, or context based on what they shared.
    
    Call this when the user provides:
    - Profile information (name, age, experience level, preferences)
    - Global goals (body fat %, FFMI targets, healthspan objectives)
    - Current focus (active cycle, upcoming workout, immediate goals)
    
    Args:
        update_description: Natural language description of what to update.
                           Examples: "User's name is Sarah, age 32"
                                    "User wants to reach 12% body fat"
                                    "User is preparing for surf session tomorrow"
    
    Returns:
        Confirmation message
    """
    if not _project_id:
        logger.error("[TOOL] update_user_context: project_id not set")
        return "Error: project_id not configured"
    
    # Get user_id from tool attribute (Phase 1 workaround)
    user_id = getattr(update_user_context, '_user_id', None)
    if not user_id:
        logger.error("[TOOL] update_user_context: user_id not set")
        return "Error: user_id not available"
    
    logger.info(f"[TOOL] update_user_context called: {update_description}")
    
    try:
        # Load current context
        current_context = get_user_context(user_id, _project_id)
        
        # Parse and update
        updated_context = parse_and_update_context(update_description, current_context)
        
        # Save to Firestore (append-only)
        save_user_context(user_id, _project_id, updated_context)
        
        return "Context updated successfully"
    except Exception as e:
        logger.error(f"[TOOL] update_user_context error: {e}")
        return f"Error updating context: {str(e)}"


@tool
def send_notification(message: str, priority: str = "normal") -> str:
    """
    Send push notification to user's device.
    
    Use sparingly and only when:
    - User's preferences allow notifications
    - The message provides clear, actionable value
    - Proactive outreach would genuinely help
    
    Args:
        message: Notification message text
        priority: "low", "normal", or "high"
    
    Returns:
        Confirmation message
    """
    # Phase 0: Just log
    logger.info(f"[TOOL] send_notification called: priority={priority}, message={message}")
    return "Notification logged (Phase 0 stub)"

GROW_PROMPT = """You are SHIFT, a wellness coaching agent using the GROW framework.

## CONVERSATION PHASES

You guide users through three phases:

1. INTAKE (First interaction)
   - Gather: name, age, experience level
   - Ask about: notification preferences
   - Understand: current fitness baseline
   - Tool: Call update_user_context with profile details

2. GLOBAL GOALS (After intake complete)
   - Explore: long-term healthspan objectives
     * Body composition targets (body fat %, FFMI)
     * Functional fitness (balance, mobility, longevity)
     * Lifestyle habits (sleep, stress, recovery)
   - Clarify: timeline and motivation
   - Tool: Call update_user_context with global goals

3. CHECK-INS (Ongoing)
   - Use GROW for each conversation:
     * Goal: What does the user want to work on right now?
     * Reality: What's their current situation and constraints?
     * Options: What small adjustments could help?
     * Will: What one concrete action will they commit to?
   - Tool: Call update_user_context when focus/goals change

## YOUR RESPONSIBILITIES

- Detect which phase the user is in
- Gather missing information before advancing to next phase
- If user mentions something from a prior phase (e.g., updates their goals during a check-in), acknowledge and update accordingly
- Use update_user_context whenever the user shares new information about themselves

## GROW FRAMEWORK (for Check-ins)

- Goal: Clarify what area of health/wellness the user wants to improve
- Reality: Understand current challenges and constraints  
- Options: Explore adjustments in fitness, nutrition, lifestyle, recovery, stress, routines
- Will: Help user choose one small, concrete action to commit to

## BOUNDARIES

You are NOT a medical professional, therapist, or diagnostician.

You must NOT:
- Provide medical advice
- Diagnose conditions
- Suggest medications or treatments
- Engage in therapy-style conversations
- Drift into unrelated topics

You should:
- Be calm, non-judgmental, supportive
- Preserve user agency
- Normalize setbacks
- Avoid overwhelming the user

## CONVERSATIONAL RULES

- Ask one question at a time
- Prefer reflection over instruction
- Prefer small actions over big plans
- If user seems stuck, offer specific examples

## CHECK-IN CADENCE

- Daily: Brief reflection on current commitment (if user initiates)
- Weekly: Restart full GROW cycle for new focus

## TOOLS AVAILABLE

- update_user_context: Call when user shares profile info, goals, focus changes, or preferences
- send_notification: Call when proactive outreach would help (RARE - respect user preferences)

## SYSTEM EVENTS

You may receive messages prefixed with [SYSTEM EVENT] containing JSON data. These are structured events from the iOS app:

- **app_opened**: User opened the app. Greet them warmly and check in.
- **card_tapped**: User tapped an intervention card. The JSON includes `intervention_key` and `suggested_action`. Respond appropriately to the action they're engaging with.
- **rating_submitted**: User submitted a rating. The JSON includes `value`. Acknowledge and continue the conversation.
- **health_metric_changed**: A health metric changed. Consider if proactive outreach would help.

When you receive a system event, respond naturally as if the user took that action. Don't mention the JSON format to the user.
"""


def create_grow_agent(project_id: str, model_name: str = "claude-sonnet-4-5-20250929"):
    # Set global project_id for tools
    set_project_id(project_id)
    
    checkpointer = FirestoreSaver(
        project_id=project_id,
        checkpoints_collection="agent_conversations"
    )

    return create_agent(
        model=ChatAnthropic(model=model_name),
        tools=[update_user_context, send_notification],
        middleware=[
            NotificationGatingMiddleware(project_id),  # Runs first - gates health_metric events
            ContextInjectionMiddleware(project_id),
        ],
        system_prompt=GROW_PROMPT,
        checkpointer=checkpointer
    )


if __name__ == "__main__":
    from langgraph.checkpoint.memory import MemorySaver
    import asyncio
    import os
    import json

    # Enable logging
    logging.basicConfig(level=logging.INFO)
    
    # Use test project ID
    test_project_id = os.environ.get("GCP_PROJECT_ID", "shift-dev-478422")
    set_project_id(test_project_id)

    agent = create_agent(
        model=ChatAnthropic(model="claude-sonnet-4-5-20250929"),
        tools=[update_user_context, send_notification],
        middleware=[
            NotificationGatingMiddleware(test_project_id),
            ContextInjectionMiddleware(test_project_id),
        ],
        system_prompt=GROW_PROMPT,
        checkpointer=MemorySaver()
    )

    async def test():
        # Set user_id for tool and middleware (Phase 1 workaround)
        test_user_id = "test_user_phase1"
        update_user_context._user_id = test_user_id
        set_middleware_user_id(test_user_id)
        
        # Test 1: User provides profile info
        print("\n=== Test 1: User provides profile info ===")
        result = await agent.ainvoke(
            {"messages": [{"role": "user", "content": "Hi, I'm Sarah and I'm 32 years old"}]},
            config={
                "configurable": {"thread_id": "test"},
                "runtime": {"user_id": test_user_id}
            }
        )
        print(result["messages"][-1].content)
        print("\n[Verify in Firestore: user_context/test_user_phase1/versions should have Sarah, age 32]")
        
        # Test 2: Agent should see context from Test 1
        print("\n=== Test 2: Agent should remember Sarah from context ===")
        result = await agent.ainvoke(
            {"messages": [{"role": "user", "content": "What's my name?"}]},
            config={
                "configurable": {"thread_id": "test"},
                "runtime": {"user_id": test_user_id}
            }
        )
        print(result["messages"][-1].content)
        print("\n[Expected: Agent says 'Sarah' based on injected context]")
        
        # Test 3: User shares goals
        print("\n=== Test 3: User shares goals ===")
        result = await agent.ainvoke(
            {"messages": [{"role": "user", "content": "I want to get to 12% body fat"}]},
            config={
                "configurable": {"thread_id": "test"},
                "runtime": {"user_id": test_user_id}
            }
        )
        print(result["messages"][-1].content)
        print("\n[Verify in Firestore: goals.long_term should include body fat goal]")
        
        # Test 4: Tool event (app opened) - using HumanMessage with event format
        print("\n=== Test 4: Tool event - app opened ===")
        tool_event = {
            "type": "app_opened",
            "timestamp": "2025-12-31T10:00:00Z"
        }
        # Tool events from iOS come as structured events, presented as system events to the agent
        event_message = f"[SYSTEM EVENT] {json.dumps(tool_event)}"
        result = await agent.ainvoke(
            {"messages": [{"role": "user", "content": event_message}]},
            config={
                "configurable": {"thread_id": "test"},
                "runtime": {"user_id": test_user_id}
            }
        )
        print(result["messages"][-1].content)
        print("\n[Expected: Agent acknowledges app opened and offers to help]")
        
        # Test 5: Tool event (card tapped)
        print("\n=== Test 5: Tool event - card tapped ===")
        tool_event = {
            "type": "card_tapped",
            "intervention_key": "stress_checkin",
            "suggested_action": "rate_stress_1_to_5",
            "context": "User tapped stress check-in card",
            "timestamp": "2025-12-31T10:30:00Z"
        }
        event_message = f"[SYSTEM EVENT] {json.dumps(tool_event)}"
        result = await agent.ainvoke(
            {"messages": [{"role": "user", "content": event_message}]},
            config={
                "configurable": {"thread_id": "test"},
                "runtime": {"user_id": test_user_id}
            }
        )
        print(result["messages"][-1].content)
        print("\n[Expected: Agent responds to stress check-in card tap]")

    asyncio.run(test())
