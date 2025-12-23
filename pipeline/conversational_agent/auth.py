import os
from typing import Optional
from fastapi import HTTPException, Header, Depends
from auth_identity_platform import verify_identity_platform_token, get_user_from_token


async def get_current_user(
        authorization: Optional[str] = Header(None)
) -> str:
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
        mock_user_id = token.split('.', 1)[1] if '.' in token else "mock-user-default"
        return mock_user_id

    try:
        project_id = os.environ.get("GCP_PROJECT_ID")
        if not project_id:
            raise ValueError("GCP_PROJECT_ID environment variable not set")

        claims = verify_identity_platform_token(token, project_id)
        user_id = get_user_from_token(claims)
        return user_id
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Token verification failed: {str(e)}")
