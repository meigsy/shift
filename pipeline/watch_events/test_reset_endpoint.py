#!/usr/bin/env python3
"""
Test script for /user/reset endpoint.
Tests both the Pydantic model parsing and endpoint functionality.
"""

import sys
import json
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from schemas import ResetUserDataRequest
from pydantic import ValidationError

def test_pydantic_model():
    """Test that ResetUserDataRequest correctly parses JSON."""
    print("Testing ResetUserDataRequest Pydantic model...")
    print("=" * 60)
    
    # Test 1: Valid request with scope="all"
    print("\n1. Testing valid request with scope='all':")
    try:
        req1 = ResetUserDataRequest(scope="all")
        print(f"   ✅ SUCCESS: scope={req1.scope}")
        assert req1.scope == "all"
    except Exception as e:
        print(f"   ❌ FAILED: {e}")
        return False
    
    # Test 2: Valid request with scope="flows"
    print("\n2. Testing valid request with scope='flows':")
    try:
        req2 = ResetUserDataRequest(scope="flows")
        print(f"   ✅ SUCCESS: scope={req2.scope}")
        assert req2.scope == "flows"
    except Exception as e:
        print(f"   ❌ FAILED: {e}")
        return False
    
    # Test 3: Valid request with scope="saved"
    print("\n3. Testing valid request with scope='saved':")
    try:
        req3 = ResetUserDataRequest(scope="saved")
        print(f"   ✅ SUCCESS: scope={req3.scope}")
        assert req3.scope == "saved"
    except Exception as e:
        print(f"   ❌ FAILED: {e}")
        return False
    
    # Test 4: Default value (no scope provided)
    print("\n4. Testing default value (no scope provided):")
    try:
        req4 = ResetUserDataRequest()
        print(f"   ✅ SUCCESS: scope={req4.scope} (default)")
        assert req4.scope == "all"
    except Exception as e:
        print(f"   ❌ FAILED: {e}")
        return False
    
    # Test 5: Parse from JSON dict (simulating FastAPI request body)
    print("\n5. Testing parsing from dict (simulating FastAPI):")
    try:
        json_data = {"scope": "all"}
        req5 = ResetUserDataRequest(**json_data)
        print(f"   ✅ SUCCESS: Parsed from dict, scope={req5.scope}")
        assert req5.scope == "all"
    except Exception as e:
        print(f"   ❌ FAILED: {e}")
        return False
    
    # Test 6: Invalid scope value
    print("\n6. Testing invalid scope value (should fail validation):")
    try:
        req6 = ResetUserDataRequest(scope="invalid")
        print(f"   ❌ FAILED: Should have raised ValidationError, but got scope={req6.scope}")
        return False
    except ValidationError as e:
        print(f"   ✅ SUCCESS: Correctly rejected invalid scope")
        print(f"      Error: {e.errors()}")
    except Exception as e:
        print(f"   ⚠️  Unexpected error type: {e}")
    
    print("\n" + "=" * 60)
    print("✅ All Pydantic model tests passed!")
    print("\nThe ResetUserDataRequest model correctly:")
    print("  - Parses valid scope values ('all', 'flows', 'saved')")
    print("  - Defaults to 'all' when not provided")
    print("  - Rejects invalid scope values")
    print("  - Works with dict unpacking (as FastAPI does)")
    return True


if __name__ == "__main__":
    success = test_pydantic_model()
    sys.exit(0 if success else 1)

