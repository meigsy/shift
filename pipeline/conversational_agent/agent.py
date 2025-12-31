from langchain.agents import create_agent
from langchain.tools import tool
from langchain_anthropic import ChatAnthropic
from langgraph_checkpoint_firestore import FirestoreSaver
import logging

from middleware import ContextInjectionMiddleware

logger = logging.getLogger(__name__)


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
    # Phase 0: Just log
    logger.info(f"[TOOL] update_user_context called: {update_description}")
    return "Context update logged (Phase 0 stub)"


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

Note: Tools are currently in Phase 0 (logging only). Use them to practice when appropriate.
"""


def create_grow_agent(project_id: str, model_name: str = "claude-sonnet-4-5-20250929"):
    checkpointer = FirestoreSaver(
        project_id=project_id,
        checkpoints_collection="agent_conversations"
    )

    return create_agent(
        model=ChatAnthropic(model=model_name),
        tools=[update_user_context, send_notification],
        middleware=[ContextInjectionMiddleware()],
        system_prompt=GROW_PROMPT,
        checkpointer=checkpointer
    )


if __name__ == "__main__":
    from langgraph.checkpoint.memory import MemorySaver
    import asyncio

    # Enable logging
    logging.basicConfig(level=logging.INFO)

    agent = create_agent(
        model=ChatAnthropic(model="claude-sonnet-4-5-20250929"),
        tools=[update_user_context, send_notification],
        middleware=[ContextInjectionMiddleware()],
        system_prompt=GROW_PROMPT,
        checkpointer=MemorySaver()
    )

    async def test():
        # Test 1: Agent should call update_user_context
        print("\n=== Test 1: User provides profile info ===")
        result = await agent.ainvoke(
            {"messages": [{"role": "user", "content": "Hi, I'm Sarah and I'm 32 years old"}]},
            config={"configurable": {"thread_id": "test"}}
        )
        print(result["messages"][-1].content)
        
        # Test 2: Continuing conversation
        print("\n=== Test 2: User shares goals ===")
        result = await agent.ainvoke(
            {"messages": [{"role": "user", "content": "I want to get to 12% body fat"}]},
            config={"configurable": {"thread_id": "test"}}
        )
        print(result["messages"][-1].content)

    asyncio.run(test())
