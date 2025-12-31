import pytest
import os
import sys
from pathlib import Path
from unittest.mock import patch
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).parent.parent.parent))


@pytest.fixture
def client():
    """Create test client with mocked environment variables."""
    with patch.dict(os.environ, {
        "GCP_PROJECT_ID": "test-project",
        "ANTHROPIC_API_KEY": "test-key"
    }):
        # Import main inside the patch context to use mocked env vars
        from conversational_agent.main import app
        yield TestClient(app)


def test_health_endpoint(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
