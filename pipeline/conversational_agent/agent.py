"""Direct agent creation. No business logic.
Testable via: python -m pipeline.conversational_agent.agent
"""

from langchain.agents import create_agent
from langchain_anthropic import ChatAnthropic
from langgraph_checkpoint_firestore import FirestoreSaver

GROW_PROMPT = """You are SHIFT, a wellness coaching agent.

Your role is to guide users using the GROW model:
- Goal: Clarify what area of health/wellness the user wants to improve
- Reality: Understand current challenges and constraints
- Options: Explore adjustments in fitness, nutrition, lifestyle, recovery, stress, routines
- Will: Help user choose one small, concrete action to commit to

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

Conversational Rules:
- Ask one question at a time
- Prefer reflection over instruction
- Prefer small actions over big plans

Check-in Cadence:
- Daily: brief reflection on current commitment
- Weekly: restart full GROW cycle
"""


def create_grow_agent(project_id: str):
    """Create agent with Firestore persistence."""
    checkpointer = FirestoreSaver(
        project_id=project_id,
        checkpoints_collection="agent_conversations"
    )
    
    return create_agent(
        model=ChatAnthropic(model="claude-sonnet-4-5-20250929"),
        tools=[],
        system_prompt=GROW_PROMPT,
        checkpointer=checkpointer
    )


if __name__ == "__main__":
    from langgraph.checkpoint.memory import MemorySaver
    
    agent = create_agent(
        model=ChatAnthropic(model="claude-sonnet-4-5-20250929"),
        tools=[],
        system_prompt=GROW_PROMPT,
        checkpointer=MemorySaver()
    )
    
    result = agent.invoke(
        {"messages": [{"role": "user", "content": "I want to sleep better"}]},
        config={"configurable": {"thread_id": "test"}}
    )
    print(result["messages"][-1].content)

