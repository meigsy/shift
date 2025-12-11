"""Tests for Cloud Function handler."""

import base64
import json
import os
from unittest.mock import Mock, patch, MagicMock
from cloudevents.http import CloudEvent

from main import state_estimator


def test_state_estimator_with_valid_pubsub_message():
    """Test Cloud Function handler with valid Pub/Sub message."""
    # Create mock CloudEvent with Pub/Sub message data
    message_data = {"user_id": "test-user", "fetched_at": "2025-01-01T00:00:00Z", "total_samples": 10}
    encoded_data = base64.b64encode(json.dumps(message_data).encode("utf-8")).decode("utf-8")
    
    # Create CloudEvent
    cloud_event = CloudEvent(
        attributes={
            "specversion": "1.0",
            "type": "google.cloud.pubsub.topic.v1.messagePublished",
            "source": "//pubsub.googleapis.com/projects/test/topics/watch_events",
            "id": "test-message-id",
        },
        data=encoded_data,
    )
    
    with patch.dict(os.environ, {"GCP_PROJECT_ID": "test-project", "BQ_DATASET_ID": "test_dataset"}):
        with patch("main.BigQueryRepository") as mock_repo_class:
            with patch("main.run_pipeline") as mock_run_pipeline:
                mock_repo = Mock()
                mock_repo_class.return_value = mock_repo
                
                # Call the function
                state_estimator(cloud_event)
                
                # Verify repository was initialized
                mock_repo_class.assert_called_once_with(
                    project_id="test-project",
                    dataset_id="test_dataset",
                )
                
                # Verify pipeline was run
                mock_run_pipeline.assert_called_once_with(
                    repository=mock_repo,
                    create_views=True,
                    run_transform=True,
                    verbose=True,
                )


def test_state_estimator_with_bytes_message():
    """Test Cloud Function handler with bytes message data."""
    message_data = {"user_id": "test-user", "fetched_at": "2025-01-01T00:00:00Z"}
    encoded_data = base64.b64encode(json.dumps(message_data).encode("utf-8"))
    
    cloud_event = CloudEvent(
        attributes={
            "specversion": "1.0",
            "type": "google.cloud.pubsub.topic.v1.messagePublished",
            "source": "//pubsub.googleapis.com/projects/test/topics/watch_events",
            "id": "test-message-id",
        },
        data=encoded_data,
    )
    
    with patch.dict(os.environ, {"GCP_PROJECT_ID": "test-project"}):
        with patch("main.BigQueryRepository") as mock_repo_class:
            with patch("main.run_pipeline") as mock_run_pipeline:
                mock_repo = Mock()
                mock_repo_class.return_value = mock_repo
                
                state_estimator(cloud_event)
                
                mock_run_pipeline.assert_called_once()


def test_state_estimator_with_missing_project_id():
    """Test Cloud Function handler raises error when GCP_PROJECT_ID is missing."""
    cloud_event = CloudEvent(
        attributes={
            "specversion": "1.0",
            "type": "google.cloud.pubsub.topic.v1.messagePublished",
            "source": "//pubsub.googleapis.com/projects/test/topics/watch_events",
            "id": "test-message-id",
        },
        data="test-data",
    )
    
    with patch.dict(os.environ, {}, clear=True):
        with patch("main.BigQueryRepository"):
            with patch("main.run_pipeline"):
                # Should raise ValueError
                try:
                    state_estimator(cloud_event)
                    assert False, "Should have raised ValueError"
                except ValueError as e:
                    assert "GCP_PROJECT_ID" in str(e)


def test_state_estimator_error_handling():
    """Test Cloud Function handler re-raises errors for retry."""
    cloud_event = CloudEvent(
        attributes={
            "specversion": "1.0",
            "type": "google.cloud.pubsub.topic.v1.messagePublished",
            "source": "//pubsub.googleapis.com/projects/test/topics/watch_events",
            "id": "test-message-id",
        },
        data="test-data",
    )
    
    with patch.dict(os.environ, {"GCP_PROJECT_ID": "test-project"}):
        with patch("main.BigQueryRepository") as mock_repo_class:
            with patch("main.run_pipeline") as mock_run_pipeline:
                mock_repo = Mock()
                mock_repo_class.return_value = mock_repo
                
                # Simulate error in pipeline
                test_error = RuntimeError("Pipeline failed")
                mock_run_pipeline.side_effect = test_error
                
                # Should re-raise the error
                try:
                    state_estimator(cloud_event)
                    assert False, "Should have raised RuntimeError"
                except RuntimeError as e:
                    assert str(e) == "Pipeline failed"















