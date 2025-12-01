"""Test fixtures and configuration."""

import pytest
from unittest.mock import Mock
from pathlib import Path

from src.repository import Repository


@pytest.fixture
def mock_repository():
    """Create a mocked repository for testing."""
    repo = Mock(spec=Repository)
    repo.execute_query = Mock(return_value=None)
    repo.execute_script = Mock(return_value=None)
    return repo
