"""FastAPI application for SHIFT backend."""

import os
from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional

from schemas import (
    AppleAuthRequest,
    AuthResponse,
    User,
    HealthDataBatch,
    WatchEventsResponse
)
from auth_apple import authenticate_with_apple
from auth_identity_platform import verify_identity_platform_token, get_user_from_token
from users_repo import users_repo

app = FastAPI(
    title="SHIFT Backend API",
    description="Backend API for SHIFT fitness OS",
    version="1.0.0"
)

# CORS middleware for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "ok"}


@app.post("/auth/apple", response_model=AuthResponse)
async def auth_apple(request: AppleAuthRequest):
    """
    Authenticate with Sign in with Apple.
    
    Accepts Apple identity token and authorization code,
    verifies with Apple, exchanges with Identity Platform,
    and returns Identity Platform tokens.
    """
    try:
        # Verify Apple token and exchange with Identity Platform
        id_token, refresh_token, expires_in, user_info = await authenticate_with_apple(
            identity_token=request.identity_token,
            authorization_code=request.authorization_code
        )
        
        # Extract user ID from Identity Platform response
        user_id = user_info.get("localId") or user_info.get("user_id")
        if not user_id:
            raise HTTPException(
                status_code=500,
                detail="Identity Platform response missing user ID"
            )
        
        # Upsert user in repository
        email = user_info.get("email")
        display_name = user_info.get("displayName")
        user = users_repo.upsert_user(
            user_id=user_id,
            email=email,
            display_name=display_name
        )
        
        return AuthResponse(
            id_token=id_token,
            refresh_token=refresh_token,
            expires_in=expires_in,
            user=user
        )
    
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Authentication failed: {str(e)}")


@app.post("/auth/apple/mock", response_model=AuthResponse)
async def auth_apple_mock(request: AppleAuthRequest):
    """
    Mock authentication endpoint for testing without Apple Developer account.
    
    Accepts any identity_token and authorization_code, returns a mock
    Identity Platform token. Use this for testing the iOS app flow.
    
    WARNING: This endpoint should be disabled in production!
    """
    import secrets
    from datetime import datetime, timedelta
    
    # Generate a mock user ID based on the provided token (for consistency)
    mock_user_id = f"mock-user-{secrets.token_hex(8)}"
    
    # Create mock user
    user = users_repo.upsert_user(
        user_id=mock_user_id,
        email="test@example.com",
        display_name="Test User"
    )
    
    # Generate a mock ID token (just a random string - not a real JWT)
    # In real testing, you'd want to generate a proper JWT, but for mock purposes
    # this works since we're not verifying it
    mock_id_token = f"mock.id.token.{secrets.token_urlsafe(32)}"
    
    return AuthResponse(
        id_token=mock_id_token,
        refresh_token=None,
        expires_in=3600,
        user=user
    )


async def get_current_user(
    authorization: Optional[str] = Header(None)
) -> User:
    """Dependency to get current authenticated user from ID token."""
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="Missing Authorization header"
        )
    
    # Extract token from "Bearer <token>"
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=401,
            detail="Invalid Authorization header format. Expected: Bearer <token>"
        )
    
    token = parts[1]
    
    try:
        # Verify Identity Platform token
        claims = verify_identity_platform_token(token)
        
        # Get user info from token
        user_id = get_user_from_token(claims)
        
        # Get user from repository
        user = users_repo.get_user(user_id)
        if not user:
            raise HTTPException(
                status_code=404,
                detail="User not found"
            )
        
        return user
    
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Token verification failed: {str(e)}")


@app.get("/me", response_model=User)
async def get_me(current_user: User = Depends(get_current_user)):
    """Get current user information."""
    return current_user


@app.post("/watch_events", response_model=WatchEventsResponse)
async def watch_events(
    batch: HealthDataBatch,
    current_user: User = Depends(get_current_user)
):
    """
    Receive health data batch from iOS app.
    
    Requires authentication. Associates health data with authenticated user.
    """
    # Calculate total samples
    total_samples = (
        len(batch.heartRate) +
        len(batch.hrv) +
        len(batch.restingHeartRate) +
        len(batch.walkingHeartRateAverage) +
        len(batch.respiratoryRate) +
        len(batch.oxygenSaturation) +
        len(batch.vo2Max) +
        len(batch.steps) +
        len(batch.activeEnergy) +
        len(batch.exerciseTime) +
        len(batch.standTime) +
        len(batch.timeInDaylight) +
        len(batch.bodyMass) +
        len(batch.bodyFatPercentage) +
        len(batch.leanBodyMass) +
        len(batch.sleep) +
        len(batch.workouts)
    )
    
    # TODO: Store health data in BigQuery or other storage
    # For now, just acknowledge receipt
    
    return WatchEventsResponse(
        message="Health data received",
        samples_received=total_samples,
        user_id=current_user.user_id
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)


