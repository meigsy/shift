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
        
        # WORKAROUND Phase 1: Store user_id in tool function attribute and middleware
        from agent import update_user_context
        from middleware import set_middleware_user_id
        update_user_context._user_id = self.user_id
        set_middleware_user_id(self.user_id)

        # Track what we've already yielded to avoid duplicates
        last_yielded_length = 0

        async for chunk in self.agent.astream(
            {"messages": [{"role": "user", "content": message}]},
            config={
                "configurable": {"thread_id": full_thread_id},
                "runtime": {"user_id": self.user_id}  # Pass to middleware
            },
            stream_mode="values"
        ):
            if chunk and "messages" in chunk:
                last_msg = chunk["messages"][-1]
                
                # ONLY yield if it's an AI/assistant message (not user or tool messages)
                if hasattr(last_msg, "type") and last_msg.type == "ai":
                    if hasattr(last_msg, "content"):
                        content = last_msg.content
                        if isinstance(content, str):
                            # Only yield new content (avoid re-yielding same text)
                            if len(content) > last_yielded_length:
                                yield content[last_yielded_length:]
                                last_yielded_length = len(content)
                        elif isinstance(content, list):
                            # Handle list content (tool calls return text in list format)
                            text_content = ""
                            for item in content:
                                if hasattr(item, "text"):
                                    text_content += item.text
                                elif isinstance(item, dict) and "text" in item:
                                    text_content += item["text"]
                            if text_content and len(text_content) > last_yielded_length:
                                yield text_content[last_yielded_length:]
                                last_yielded_length = len(text_content)


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
