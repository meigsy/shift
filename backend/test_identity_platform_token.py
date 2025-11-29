"""
Test script for Identity Platform token verification.
This helps test the token verification logic with real Identity Platform tokens.

To use:
1. Get a real Identity Platform token from your GCP project
2. Set it in the ID_TOKEN variable below
3. Run: python test_identity_platform_token.py
"""

import os
import sys
from auth_identity_platform import verify_identity_platform_token, get_user_from_token


def test_token_verification():
    """Test Identity Platform token verification."""
    
    # Set your test token here (get from Identity Platform console or iOS app)
    ID_TOKEN = os.getenv("TEST_ID_TOKEN", "")
    
    if not ID_TOKEN:
        print("=" * 60)
        print("Identity Platform Token Verification Test")
        print("=" * 60)
        print()
        print("Usage:")
        print("  export TEST_ID_TOKEN='your-token-here'")
        print("  python test_identity_platform_token.py")
        print()
        print("Or set ID_TOKEN variable in this script.")
        print()
        print("To get a test token:")
        print("  1. Deploy backend to Cloud Run")
        print("  2. Use iOS app to sign in (if you have Apple Developer account)")
        print("  3. Copy the id_token from the response")
        print("  4. Or use Identity Platform console to generate test tokens")
        print("=" * 60)
        return
    
    # Set required environment variables
    if not os.getenv("GCP_PROJECT_ID") and not os.getenv("IDENTITY_PLATFORM_PROJECT_ID"):
        print("⚠️  Warning: GCP_PROJECT_ID not set. Token verification may fail.")
        print("   Set it with: export GCP_PROJECT_ID='your-project-id'")
        print()
    
    try:
        print("Verifying token...")
        print(f"Token (first 50 chars): {ID_TOKEN[:50]}...")
        print()
        
        claims = verify_identity_platform_token(ID_TOKEN)
        print("✅ Token verified successfully!")
        print()
        print("Claims:")
        for key, value in claims.items():
            print(f"  {key}: {value}")
        print()
        
        user_id = get_user_from_token(claims)
        print(f"✅ User ID extracted: {user_id}")
        
    except ValueError as e:
        print(f"❌ Token verification failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    test_token_verification()

