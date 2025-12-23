"""Tests for agent.py - minimal happy path."""

import pytest
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from langgraph.checkpoint.memory import MemorySaver
from langchain.agents import create_agent
from langchain_anthropic import ChatAnthropic
from conversational_agent.agent import GROW_PROMPT, create_grow_agent


def test_agent_responds_to_message():
    """Test agent responds to single message."""
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
    
    assert result is not None
    assert "messages" in result
    assert len(result["messages"]) > 0
    assert hasattr(result["messages"][-1], "content")

