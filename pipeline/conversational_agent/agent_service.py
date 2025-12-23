"""Business logic layer. No HTTP concerns.
Handles user isolation and thread management.
Testable via: python -m pipeline.conversational_agent.agent_service
"""

from dataclasses import dataclass


@dataclass
class ChatRequest:
    user_id: str
    message: str
    thread_id: str | None = None


class AgentService:
    def __init__(self, user_id: str, agent):
        self.user_id = user_id
        self.agent = agent
    
    def _get_thread_id(self, requested: str | None) -> str:
        """User isolation via thread_id format."""
        if requested:
            return f"user_{self.user_id}_thread_{requested}"
        return f"user_{self.user_id}_active"
    
    async def chat_stream(self, request: ChatRequest):
        """Stream agent responses."""
        thread_id = self._get_thread_id(request.thread_id)
        
        async for chunk in self.agent.astream(
            {"messages": [{"role": "user", "content": request.message}]},
            config={"configurable": {"thread_id": thread_id}},
            stream_mode="messages"
        ):
            for message in chunk:
                if hasattr(message, "content") and message.content:
                    yield message.content


if __name__ == "__main__":
    import asyncio
    import sys
    from pathlib import Path
    from langgraph.checkpoint.memory import MemorySaver
    from langchain.agents import create_agent
    from langchain_anthropic import ChatAnthropic
    
    # Add current directory to path for imports
    sys.path.insert(0, str(Path(__file__).parent))
    from agent import GROW_PROMPT
    
    async def test_service():
        agent = create_agent(
            model=ChatAnthropic(model="claude-sonnet-4-5-20250929"),
            tools=[],
            system_prompt=GROW_PROMPT,
            checkpointer=MemorySaver()
        )
        
        service = AgentService(user_id="test_user", agent=agent)
        request = ChatRequest(
            user_id="test_user",
            message="I want to sleep better",
            thread_id=None
        )
        
        print("Streaming response:")
        async for chunk in service.chat_stream(request):
            print(chunk, end="", flush=True)
        print("\n")
    
    asyncio.run(test_service())

