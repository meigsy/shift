import pytest
import os
import sys
from pathlib import Path
from fastapi.testclient import TestClient
from unittest.mock import patch

# Set required environment variables for testing
os.environ["GCP_PROJECT_ID"] = "test-project"
os.environ["BQ_DATASET_ID"] = "shift_data"

sys.path.insert(0, str(Path(__file__).parent.parent))

from watch_events.main import app, User, get_current_user


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def mock_user():
    """Mock authenticated user."""
    return User(user_id="test-user-123", email="test@example.com")


def test_context_returns_getting_started(client, mock_user):
    """Test that GET /context returns getting_started with correct action structure."""
    
    # Mock the get_current_user dependency
    def override_get_current_user():
        return mock_user
    
    app.dependency_overrides[get_current_user] = override_get_current_user
    
    # Mock the repository methods
    with patch('watch_events.main.ContextRepository') as MockRepo:
        mock_repo_instance = MockRepo.return_value
        mock_repo_instance.has_completed_flow.return_value = False
        mock_repo_instance.get_latest_state_estimate.return_value = None
        mock_repo_instance.get_created_interventions_for_user.return_value = []
        mock_repo_instance.get_catalog_for_keys.return_value = {}
        mock_repo_instance.get_saved_interventions.return_value = []
        
        # Make the request
        response = client.get("/context")
        
        # Assert response is successful
        assert response.status_code == 200
        
        # Parse response
        data = response.json()
        
        # Assert structure
        assert "interventions" in data
        assert isinstance(data["interventions"], list)
        assert len(data["interventions"]) > 0
        
        # Get the first intervention (should be getting_started)
        getting_started = data["interventions"][0]
        
        # Assert basic fields
        assert getting_started["intervention_key"] == "getting_started_v1"
        assert getting_started["title"] == "Welcome to SHIFT"
        assert getting_started["status"] == "created"
        assert getting_started["surface"] == "notification"
        
        # Assert action structure exists
        assert "action" in getting_started
        action = getting_started["action"]
        assert action["type"] == "full_screen_flow"
        
        # Assert completion_action exists
        assert "completion_action" in action
        completion_action = action["completion_action"]
        assert completion_action["type"] == "chat_prompt"
        assert "prompt" in completion_action
        assert "GROW" in completion_action["prompt"]
        
        # Assert pages structure exists
        assert "pages" in getting_started
        pages = getting_started["pages"]
        assert isinstance(pages, list)
        assert len(pages) == 4
        
        # Assert page templates
        assert pages[0]["template"] == "hero"
        assert pages[1]["template"] == "feature_list"
        assert pages[2]["template"] == "bullet_list"
        assert pages[3]["template"] == "cta"
        
        # Assert hero page content
        assert pages[0]["title"] == "Welcome to SHIFT"
        assert pages[0]["subtitle"] == "Your personal health operating system"
        
        # Assert feature_list page content
        assert pages[1]["title"] == "Mind · Body · Bell"
        assert "features" in pages[1]
        assert len(pages[1]["features"]) == 3
        assert pages[1]["features"][0]["icon"] == "brain.head.profile"
        
        # Assert bullet_list page content
        assert pages[2]["title"] == "How it works"
        assert "bullets" in pages[2]
        assert len(pages[2]["bullets"]) == 3
        
        # Assert cta page content
        assert pages[3]["title"] == "Ready to begin?"
        assert pages[3]["button_text"] == "Start"
    
    # Clean up
    app.dependency_overrides.clear()


def test_context_hides_getting_started_when_completed(client, mock_user):
    """Test that GET /context does NOT return getting_started when flow is completed."""
    
    # Mock the get_current_user dependency
    def override_get_current_user():
        return mock_user
    
    app.dependency_overrides[get_current_user] = override_get_current_user
    
    # Mock the repository methods - flow is completed
    with patch('watch_events.main.ContextRepository') as MockRepo:
        mock_repo_instance = MockRepo.return_value
        mock_repo_instance.has_completed_flow.return_value = True  # Flow completed!
        mock_repo_instance.get_latest_state_estimate.return_value = None
        mock_repo_instance.get_created_interventions_for_user.return_value = []
        mock_repo_instance.get_catalog_for_keys.return_value = {}
        mock_repo_instance.get_saved_interventions.return_value = []
        
        # Make the request
        response = client.get("/context")
        
        # Assert response is successful
        assert response.status_code == 200
        
        # Parse response
        data = response.json()
        
        # Assert structure
        assert "interventions" in data
        assert isinstance(data["interventions"], list)
        
        # Assert getting_started is NOT in the list
        getting_started_keys = [i.get("intervention_key") for i in data["interventions"]]
        assert "getting_started_v1" not in getting_started_keys
    
    # Clean up
    app.dependency_overrides.clear()


def test_getting_started_has_unique_trace_ids(client, mock_user):
    """Test that each getting_started intervention has a unique trace_id (not hardcoded)."""
    
    # Mock the get_current_user dependency
    def override_get_current_user():
        return mock_user
    
    app.dependency_overrides[get_current_user] = override_get_current_user
    
    # Mock the repository methods
    with patch('watch_events.main.ContextRepository') as MockRepo:
        mock_repo_instance = MockRepo.return_value
        mock_repo_instance.has_completed_flow.return_value = False
        mock_repo_instance.get_latest_state_estimate.return_value = None
        mock_repo_instance.get_created_interventions_for_user.return_value = []
        mock_repo_instance.get_catalog_for_keys.return_value = {}
        mock_repo_instance.get_saved_interventions.return_value = []
        
        # Make first request
        response1 = client.get("/context")
        assert response1.status_code == 200
        data1 = response1.json()
        
        # Make second request
        response2 = client.get("/context")
        assert response2.status_code == 200
        data2 = response2.json()
        
        # Get trace_ids from getting_started interventions
        trace_id_1 = data1["interventions"][0]["trace_id"]
        trace_id_2 = data2["interventions"][0]["trace_id"]
        
        # Assert both are UUIDs (not hardcoded)
        assert trace_id_1 != "getting-started-trace-id", "trace_id should not be hardcoded"
        assert trace_id_2 != "getting-started-trace-id", "trace_id should not be hardcoded"
        
        # Assert they are unique (different UUIDs per request)
        assert trace_id_1 != trace_id_2, "Each request should generate a unique trace_id"
        
        # Assert they look like UUIDs (36 chars with dashes)
        assert len(trace_id_1) == 36, "trace_id should be UUID format"
        assert len(trace_id_2) == 36, "trace_id should be UUID format"
    
    # Clean up
    app.dependency_overrides.clear()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
