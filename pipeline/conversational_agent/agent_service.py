class AgentService:
    def __init__(self, user_id: str, agent):
        self.user_id = user_id
        self.agent = agent

    def _get_thread_id(self, requested: str | None) -> str:
        if requested:
            return f"user_{self.user_id}_thread_{requested}"
        return f"user_{self.user_id}_active"

    async def chat_stream(self, message: str, thread_id: str | None = None):
        full_thread_id = self._get_thread_id(thread_id)

        async for chunk in self.agent.astream(
            {"messages": [{"role": "user", "content": message}]},
            config={"configurable": {"thread_id": full_thread_id}},
            stream_mode="values"
        ):
            if chunk and "messages" in chunk:
                last_msg = chunk["messages"][-1]
                if hasattr(last_msg, "content") and last_msg.content:
                    yield last_msg.content


if __name__ == "__main__":
    import os
    import asyncio
    from langgraph.checkpoint.memory import MemorySaver
    from langchain.agents import create_agent
    from langchain_anthropic import ChatAnthropic
    from agent import GROW_PROMPT

    test_agent = create_agent(
        model=ChatAnthropic(model="claude-sonnet-4-5-20250929"),
        tools=[],
        system_prompt=GROW_PROMPT,
        checkpointer=MemorySaver()
    )

    service = AgentService(user_id="test_user", agent=test_agent)

    async def test():
        async for chunk in service.chat_stream("I want to sleep better"):
            print(chunk, end="", flush=True)
        print()

    asyncio.run(test())
