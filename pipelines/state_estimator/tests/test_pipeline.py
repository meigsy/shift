"""Unit tests for state estimator pipeline."""

from pathlib import Path
from unittest.mock import Mock, call

from src.main import run_pipeline


def test_run_pipeline_executes_views_and_transform(mock_repository, tmp_path):
    """Test that run_pipeline calls repository methods correctly."""
    base_path = Path(__file__).parent.parent
    
    run_pipeline(
        repository=mock_repository,
        create_views=True,
        run_transform=True,
        verbose=False,
    )
    
    # Verify execute_script was called for views
    views_path = base_path / "sql" / "views.sql"
    assert call(views_path, verbose=False) in mock_repository.execute_script.call_args_list
    
    # Verify execute_script was called for transform
    transform_path = base_path / "sql" / "transform.sql"
    assert call(transform_path, verbose=False) in mock_repository.execute_script.call_args_list


def test_run_pipeline_skips_views_when_requested(mock_repository):
    """Test that run_pipeline can skip creating views."""
    base_path = Path(__file__).parent.parent
    
    run_pipeline(
        repository=mock_repository,
        create_views=False,
        run_transform=True,
        verbose=False,
    )
    
    # Verify views were not called
    views_path = base_path / "sql" / "views.sql"
    views_calls = [c for c in mock_repository.execute_script.call_args_list 
                   if c[0][0] == views_path]
    assert len(views_calls) == 0, "Views should not be executed when skipped"
    
    # Verify transform was still called
    transform_path = base_path / "sql" / "transform.sql"
    transform_calls = [c for c in mock_repository.execute_script.call_args_list 
                      if c[0][0] == transform_path]
    assert len(transform_calls) == 1, "Transform should still be executed"


def test_run_pipeline_skips_transform_when_requested(mock_repository):
    """Test that run_pipeline can skip transformation."""
    base_path = Path(__file__).parent.parent
    
    run_pipeline(
        repository=mock_repository,
        create_views=True,
        run_transform=False,
        verbose=False,
    )
    
    # Verify views were called
    views_path = base_path / "sql" / "views.sql"
    views_calls = [c for c in mock_repository.execute_script.call_args_list 
                   if c[0][0] == views_path]
    assert len(views_calls) == 1, "Views should be executed"
    
    # Verify transform was not called
    transform_path = base_path / "sql" / "transform.sql"
    transform_calls = [c for c in mock_repository.execute_script.call_args_list 
                      if c[0][0] == transform_path]
    assert len(transform_calls) == 0, "Transform should not be executed when skipped"
