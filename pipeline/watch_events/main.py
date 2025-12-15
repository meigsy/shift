"""FastAPI application for SHIFT backend."""

import secrets
from datetime import datetime, timedelta
from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional

from schemas import (
    AppleAuthRequest,
    AuthResponse,
    User,
    HealthDataBatch,
    WatchEventsResponse,
    AppInteractionRequest
)
from auth_apple import authenticate_with_apple
from auth_identity_platform import verify_identity_platform_token, get_user_from_token
from users_repo import users_repo
from services.ingestion import process_watch_events
from uuid import uuid4
import os

from context_repository import ContextRepository

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

    # Handle mock tokens for testing (bypass JWT verification)
    if token.startswith("mock."):
        # For mock tokens, use a default mock user
        # This allows testing the full flow without real Identity Platform tokens
        mock_user_id = "mock-user-default"
        user = users_repo.get_user(mock_user_id)
        if not user:
            # Create default mock user if it doesn't exist
            user = users_repo.upsert_user(
                user_id=mock_user_id,
                email="test@example.com",
                display_name="Test User"
            )
        return user

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
    
    Delegates to ingestion service for deduplication, storage, and triggering.
    """
    try:
        # Debug: Log trace_id status
        print(f"📥 Received batch from user {current_user.user_id}, trace_id: {batch.trace_id}")
        result = process_watch_events(batch, current_user.user_id)
        
        return WatchEventsResponse(
            message=result["message"],
            samples_received=result["samples_received"],
            user_id=current_user.user_id
        )
    except Exception as e:
        print(f"❌ Ingestion error: {e}")
        raise HTTPException(status_code=500, detail="Failed to process health data")


@app.post("/app_interactions")
async def app_interactions(
        interaction: AppInteractionRequest,
        current_user: User = Depends(get_current_user)
):
    """
    Receive app interaction events from iOS app.
    
    Tracks user interactions with interventions (shown, tapped, dismissed).
    Stores events in BigQuery for traceability analysis.
    """
    try:
        # Verify user_id matches authenticated user
        if interaction.user_id != current_user.user_id:
            raise HTTPException(
                status_code=403,
                detail="User ID in request does not match authenticated user"
            )
        
        # Import BigQuery client
        from google.cloud import bigquery
        import os
        
        project_id = os.getenv("GCP_PROJECT_ID")
        if not project_id:
            raise HTTPException(
                status_code=500,
                detail="GCP_PROJECT_ID not configured"
            )
        
        bq_client = bigquery.Client(project=project_id)
        table_id = f"{project_id}.shift_data.app_interactions"
        
        # Generate interaction_id
        interaction_id = str(uuid4())
        
        # Prepare row for insertion
        rows_to_insert = [
            {
                "interaction_id": interaction_id,
                "trace_id": interaction.trace_id,
                "user_id": interaction.user_id,
                "intervention_instance_id": interaction.intervention_instance_id,
                "event_type": interaction.event_type,
                "timestamp": interaction.timestamp.isoformat()
            }
        ]
        
        # Insert into BigQuery
        errors = bq_client.insert_rows_json(table_id, rows_to_insert)
        if errors:
            print(f"❌ BigQuery insert errors: {errors}")
            raise HTTPException(
                status_code=500,
                detail=f"Failed to store interaction event: {errors}"
            )
        
        print(f"✅ Stored interaction event: {interaction_id} for trace_id: {interaction.trace_id}")
        
        return {
            "status": "success",
            "message": "Interaction event recorded",
            "interaction_id": interaction_id
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Interaction ingestion error: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to process interaction event: {str(e)}")


@app.get("/context")
async def get_context(
        current_user: User = Depends(get_current_user)
):
    """Read-only aggregator endpoint for Home screen context.

    Returns:
        {
          "state_estimate": { ... } | null,
          "interventions": [ { ... }, ... ]
        }

    This endpoint is PURE READ:
    - Does not run the intervention selector
    - Does not create or update any rows
    """
    try:
        project_id = os.getenv("GCP_PROJECT_ID")
        if not project_id:
            raise HTTPException(
                status_code=500,
                detail="GCP_PROJECT_ID not configured"
            )

        dataset_id = os.getenv("BQ_DATASET_ID", "shift_data")
        repo = ContextRepository(project_id=project_id, dataset_id=dataset_id)

        user_id = current_user.user_id

        # Latest state estimate (optional)
        state_estimate = repo.get_latest_state_estimate(user_id=user_id)

        # All created intervention instances for this user
        instances = repo.get_created_interventions_for_user(user_id=user_id)

        # Look up catalog details for all intervention_keys
        keys = list({instance["intervention_key"] for instance in instances})
        catalog_by_key = repo.get_catalog_for_keys(keys)

        # Build denormalized interventions payload
        interventions = []
        for instance in instances:
            catalog = catalog_by_key.get(instance["intervention_key"])
            if not catalog:
                # If catalog entry is missing, skip but keep endpoint robust
                continue

            # Ensure trace_id is present for 100% traceability; if missing, leave
            # as-is here (selector / pipelines are responsible for generating it).
            interventions.append(
                {
                    "intervention_instance_id": instance["intervention_instance_id"],
                    "user_id": instance["user_id"],
                    "trace_id": instance["trace_id"],
                    "metric": instance["metric"],
                    "level": instance["level"],
                    "surface": instance["surface"],
                    "intervention_key": instance["intervention_key"],
                    "title": catalog["title"],
                    "body": catalog["body"],
                    "created_at": instance["created_at"].isoformat() if instance["created_at"] else None,
                    "scheduled_at": instance["scheduled_at"].isoformat() if instance["scheduled_at"] else None,
                    "sent_at": instance["sent_at"].isoformat() if instance["sent_at"] else None,
                    "status": instance["status"],
                }
            )

        # Serialize state_estimate to JSON-friendly form
        state_payload = None
        if state_estimate is not None:
            state_payload = {
                "user_id": state_estimate["user_id"],
                "timestamp": state_estimate["timestamp"].isoformat()
                if isinstance(state_estimate["timestamp"], datetime)
                else state_estimate["timestamp"],
                "trace_id": state_estimate["trace_id"],
                "recovery": state_estimate["recovery"],
                "readiness": state_estimate["readiness"],
                "stress": state_estimate["stress"],
                "fatigue": state_estimate["fatigue"],
            }

        return {
            "state_estimate": state_payload,
            "interventions": interventions,
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Context endpoint error: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch context payload")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
