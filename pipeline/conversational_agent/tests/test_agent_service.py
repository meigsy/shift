"""Tests for agent_service.py - minimal happy path."""

import pytest
import sys
from pathlib import Path
from unittest.mock import Mock

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from conversational_agent.agent_service import AgentService, ChatRequest


def test_thread_id_generation():
    """Test thread_id generation includes user_id prefix."""
    mock_agent = Mock()
    
    service = AgentService(user_id="test_user_123", agent=mock_agent)
    
    thread_id_default = service._get_thread_id(None)
    assert thread_id_default == "user_test_user_123_active"
    
    thread_id_custom = service._get_thread_id("custom_thread")
    assert thread_id_custom == "user_test_user_123_thread_custom_thread"


def test_user_isolation():
    """Verify user isolation (different user_ids produce different thread_ids)."""
    mock_agent = Mock()
    
    service1 = AgentService(user_id="user1", agent=mock_agent)
    service2 = AgentService(user_id="user2", agent=mock_agent)
    
    thread_id1 = service1._get_thread_id("same_thread")
    thread_id2 = service2._get_thread_id("same_thread")
    
    assert thread_id1 != thread_id2
    assert thread_id1 == "user_user1_thread_same_thread"
    assert thread_id2 == "user_user2_thread_same_thread"

