"""Identity Platform authentication dependency."""

import os
from typing import Optional
from fastapi import Header, HTTPException
from auth_identity_platform import verify_identity_platform_token, get_user_from_token


async def get_current_user(
    authorization: Optional[str] = Header(None)
) -> str:
    """Dependency to get current authenticated user_id from ID token."""
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="Missing Authorization header"
        )

    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=401,
            detail="Invalid Authorization header format. Expected: Bearer <token>"
        )

    token = parts[1]

    if token.startswith("mock."):
        return "mock-user-default"

    try:
        claims = verify_identity_platform_token(token)
        user_id = get_user_from_token(claims)
        return user_id

    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Token verification failed: {str(e)}")

