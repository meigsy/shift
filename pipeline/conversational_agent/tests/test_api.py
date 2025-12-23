"""Tests for FastAPI endpoints - minimal happy path."""

import pytest
import os
import sys
from pathlib import Path
from fastapi.testclient import TestClient

# Set required environment variables before importing
os.environ["GCP_PROJECT_ID"] = "test-project"
os.environ["ANTHROPIC_API_KEY"] = "test-key"

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from conversational_agent.main import app


@pytest.fixture
def client():
    """Create test client."""
    return TestClient(app)


def test_health_endpoint(client):
    """Test /health endpoint returns 200."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

