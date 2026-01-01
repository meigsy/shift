import pytest
import os
import time
from user_context import (
    UserGoalsAndContext,
    Profile,
    Goals,
    Context,
    parse_and_update_context,
    get_user_context,
    save_user_context
)


def test_parse_name_and_age():
    """Test parsing profile information."""
    context = UserGoalsAndContext()
    updated = parse_and_update_context("User's name is Sarah, age 32", context)
    
    assert updated.profile.name == "Sarah"
    assert updated.profile.age == 32


def test_parse_goal():
    """Test parsing goal information."""
    context = UserGoalsAndContext()
    updated = parse_and_update_context("User wants to reach 12% body fat", context)
    
    assert any("body fat" in goal.lower() for goal in updated.goals.long_term)


def test_parse_experience_level():
    """Test parsing experience level."""
    context = UserGoalsAndContext()
    updated = parse_and_update_context("User is a beginner", context)
    
    assert updated.profile.experience_level == "beginner"


def test_parse_experience_level_intermediate():
    """Test parsing intermediate experience level."""
    context = UserGoalsAndContext()
    updated = parse_and_update_context("User has intermediate experience", context)
    
    assert updated.profile.experience_level == "intermediate"


def test_parse_experience_level_advanced():
    """Test parsing advanced experience level."""
    context = UserGoalsAndContext()
    updated = parse_and_update_context("User is advanced", context)
    
    assert updated.profile.experience_level == "advanced"


def test_parse_current_focus():
    """Test parsing current focus updates."""
    context = UserGoalsAndContext()
    updated = parse_and_update_context("User is preparing for surf session tomorrow", context)
    
    assert updated.goals.current_focus == "User is preparing for surf session tomorrow"


def test_parse_multiple_goals():
    """Test parsing multiple goals."""
    context = UserGoalsAndContext()
    context = parse_and_update_context("User wants to reach 12% body fat", context)
    context = parse_and_update_context("User wants to improve sleep quality", context)
    
    assert len(context.goals.long_term) == 2
    assert any("body fat" in goal.lower() for goal in context.goals.long_term)
    assert any("sleep" in goal.lower() for goal in context.goals.long_term)


def test_parse_does_not_duplicate_goals():
    """Test that the same goal isn't added twice."""
    context = UserGoalsAndContext()
    context = parse_and_update_context("User wants to reach 12% body fat", context)
    context = parse_and_update_context("User wants to reach 12% body fat", context)
    
    assert len(context.goals.long_term) == 1


@pytest.mark.skipif(
    not os.environ.get("GCP_PROJECT_ID"),
    reason="GCP_PROJECT_ID not set"
)
def test_firestore_round_trip():
    """Test save and load from Firestore (append-only versioning)."""
    project_id = os.environ["GCP_PROJECT_ID"]
    test_user_id = f"test_user_{int(time.time())}"
    
    # Create context
    context = UserGoalsAndContext()
    context.profile.name = "TestUser"
    context.profile.age = 30
    context.goals.long_term = ["Test goal"]
    
    # Save
    save_user_context(test_user_id, project_id, context)
    
    # Wait briefly for Firestore write
    time.sleep(1)
    
    # Load latest
    loaded = get_user_context(test_user_id, project_id)
    
    assert loaded.profile.name == "TestUser"
    assert loaded.profile.age == 30
    assert "Test goal" in loaded.goals.long_term


@pytest.mark.skipif(
    not os.environ.get("GCP_PROJECT_ID"),
    reason="GCP_PROJECT_ID not set"
)
def test_firestore_versioning():
    """Test that multiple saves create multiple versions."""
    project_id = os.environ["GCP_PROJECT_ID"]
    test_user_id = f"test_user_versions_{int(time.time())}"
    
    # Save version 1
    context1 = UserGoalsAndContext()
    context1.profile.name = "Version1"
    save_user_context(test_user_id, project_id, context1)
    
    time.sleep(1)
    
    # Save version 2
    context2 = UserGoalsAndContext()
    context2.profile.name = "Version2"
    save_user_context(test_user_id, project_id, context2)
    
    time.sleep(1)
    
    # Load latest should be version 2
    loaded = get_user_context(test_user_id, project_id)
    assert loaded.profile.name == "Version2"
    
    # Both versions should exist in Firestore
    # (Manual verification: check Firestore console for 2 docs in versions subcollection)


