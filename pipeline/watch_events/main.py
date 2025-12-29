"""FastAPI application for SHIFT backend."""

import secrets
from datetime import datetime, timedelta, timezone
from fastapi import FastAPI, HTTPException, Depends, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from typing import Optional, Dict, Any

from schemas import (
    AppleAuthRequest,
    AuthResponse,
    User,
    HealthDataBatch,
    WatchEventsResponse,
    AppInteractionRequest,
    ResetUserDataRequest
)
from auth_apple import authenticate_with_apple
from auth_identity_platform import verify_identity_platform_token, get_user_from_token
from users_repo import users_repo
from services.ingestion import process_watch_events
from uuid import uuid4
import os
import json

from context_repository import ContextRepository
from google.cloud import bigquery

# Lazy import intervention selector modules (for creating getting_started instance)
# These are only used in /context endpoint and may not be available in all environments
def _get_intervention_selector_modules():
    """Lazily import intervention selector modules if available."""
    try:
        import sys
        intervention_selector_path = os.path.join(os.path.dirname(__file__), '..', 'intervention_selector')
        if intervention_selector_path not in sys.path:
            sys.path.insert(0, intervention_selector_path)
        from src.catalog import get_intervention
        from src.bigquery_client import BigQueryClient
        return get_intervention, BigQueryClient
    except (ImportError, FileNotFoundError) as e:
        print(f"⚠️ Intervention selector modules not available: {e}")
        return None, None

app = FastAPI(
    title="SHIFT Backend API",
    description="Backend API for SHIFT fitness OS",
    version="1.0.0"
)

# Log registered routes on startup
@app.on_event("startup")
async def startup_event():
    routes = []
    for route in app.routes:
        if hasattr(route, "methods") and hasattr(route, "path"):
            methods = list(route.methods) if route.methods else []
            routes.append(f"{methods} {route.path}")
    print(f"🚀 FastAPI startup: Registered {len(routes)} routes:")
    for route_str in routes:
        print(f"   {route_str}")
    # Check if /user/reset is registered
    user_reset_found = any("/user/reset" in r for r in routes)
    if user_reset_found:
        print(f"   ✅ /user/reset endpoint is registered")
    else:
        print(f"   ❌ /user/reset endpoint NOT FOUND in registered routes!")

# CORS middleware for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Handle FastAPI request validation errors (e.g., Pydantic model parsing failures)."""
    body_bytes = await request.body()
    body_str = body_bytes.decode('utf-8') if body_bytes else None
    
    # #region agent log
    log_entry_val = {
        "location": "main.py:53",
        "message": "RequestValidationError caught",
        "data": {
            "path": request.url.path,
            "method": request.method,
            "errors": exc.errors(),
            "body_preview": body_str[:200] if body_str else None
        },
        "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        "sessionId": "debug-session",
        "runId": "run1",
        "hypothesisId": "H"
    }
    print(f"🔍 [DEBUG] VALIDATION ERROR: {json.dumps(log_entry_val)}")
    try:
        with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
            f.write(json.dumps(log_entry_val) + "\n")
    except Exception as e:
        print(f"⚠️ [DEBUG] Could not write log file: {e}")
    # #endregion
    return JSONResponse(
        status_code=422,
        content={"detail": exc.errors(), "body": body_str}
    )


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "ok"}


@app.post("/user/reset/test")
async def reset_user_data_test(request: ResetUserDataRequest):
    """Test endpoint without auth to verify routing works."""
    return {"status": "ok", "scope": request.scope, "message": "Route is working"}


@app.get("/debug/routes")
async def debug_routes():
    """Debug endpoint to list all registered routes."""
    routes = []
    for route in app.routes:
        if hasattr(route, "methods") and hasattr(route, "path"):
            routes.append({
                "path": route.path,
                "methods": list(route.methods),
                "name": getattr(route, "name", "unknown")
            })
    return {"routes": routes, "total": len(routes)}


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
    # #region agent log
    log_entry_auth = {
        "location": "main.py:173",
        "message": "get_current_user entry",
        "data": {"has_authorization": authorization is not None, "auth_header_preview": authorization[:30] + "..." if authorization and len(authorization) > 30 else authorization},
        "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        "sessionId": "debug-session",
        "runId": "run1",
        "hypothesisId": "G"
    }
    print(f"🔍 [DEBUG] {json.dumps(log_entry_auth)}")
    try:
        with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
            f.write(json.dumps(log_entry_auth) + "\n")
    except Exception as e:
        print(f"⚠️ [DEBUG] Could not write log file: {e}")
    # #endregion
    
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
    
    # #region agent log
    log_entry_auth2 = {
        "location": "main.py:155",
        "message": "token extracted",
        "data": {"token_preview": token[:30] + "..." if len(token) > 30 else token, "is_mock": token.startswith("mock.")},
        "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        "sessionId": "debug-session",
        "runId": "run1",
        "hypothesisId": "G"
    }
    try:
        with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
            f.write(json.dumps(log_entry_auth2) + "\n")
    except Exception:
        pass
    # #endregion

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
        
        # #region agent log
        log_entry_auth3 = {
            "location": "main.py:171",
            "message": "mock user returned",
            "data": {"user_id": user.user_id if user else "None"},
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "G"
        }
        try:
            with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
                f.write(json.dumps(log_entry_auth3) + "\n")
        except Exception:
            pass
        # #endregion
        
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
        row_data = {
            "interaction_id": interaction_id,
            "trace_id": interaction.trace_id,
            "user_id": interaction.user_id,
            "intervention_instance_id": interaction.intervention_instance_id,
            "event_type": interaction.event_type,
            "timestamp": interaction.timestamp.isoformat()
        }
        
        # Add payload if present (must be JSON string for BigQuery JSON type)
        if interaction.payload is not None:
            row_data["payload"] = json.dumps(interaction.payload)
        
        rows_to_insert = [row_data]
        
        # Insert into BigQuery
        errors = bq_client.insert_rows_json(table_id, rows_to_insert)
        if errors:
            print(f"❌ BigQuery insert errors: {errors}")
            raise HTTPException(
                status_code=500,
                detail=f"Failed to store interaction event: {errors}"
            )
        
        print(f"✅ Stored interaction event: {interaction_id} for trace_id: {interaction.trace_id}")
        
        # Update intervention_instance status based on event_type
        # KISS: Single source of truth - backend updates status, UI reflects it
        print(f"🔍 Checking if status update needed: event_type={interaction.event_type}, intervention_instance_id={interaction.intervention_instance_id}")
        
        if interaction.event_type in ("tapped", "dismissed"):
            new_status = "accepted" if interaction.event_type == "tapped" else "dismissed"
            print(f"🔄 Updating intervention_instance {interaction.intervention_instance_id} status to: {new_status}")
            
            # Update intervention_instance status
            instances_table_id = f"{project_id}.shift_data.intervention_instances"
            update_query = f"""
                UPDATE `{instances_table_id}`
                SET status = @new_status
                WHERE intervention_instance_id = @intervention_instance_id
            """
            
            job_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("new_status", "STRING", new_status),
                    bigquery.ScalarQueryParameter("intervention_instance_id", "STRING", interaction.intervention_instance_id),
                ]
            )
            
            try:
                print(f"📝 Executing UPDATE query for intervention_instance_id: {interaction.intervention_instance_id}")
                query_job = bq_client.query(update_query, job_config=job_config)
                result = query_job.result()  # Wait for completion
                num_rows_updated = query_job.num_dml_affected_rows if hasattr(query_job, 'num_dml_affected_rows') else "unknown"
                print(f"✅ Updated intervention_instance {interaction.intervention_instance_id} status to: {new_status} (rows affected: {num_rows_updated})")
            except Exception as e:
                # Log error but don't fail the request - interaction was already logged
                print(f"⚠️ Failed to update intervention_instance status: {e}")
                import traceback
                print(f"⚠️ Traceback: {traceback.format_exc()}")
        else:
            print(f"⏭️ Skipping status update - event_type '{interaction.event_type}' not in ('tapped', 'dismissed')")
        
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

        # Check if getting_started should be shown and create instance if needed
        # This handles the case where selector hasn't run yet (no state estimate)
        getting_started_completed = repo.has_completed_flow(user_id, "getting_started", "v1")
        flow_requested = False
        try:
            # Check for recent flow_requested events (within last 5 minutes)
            query = f"""
                SELECT COUNT(*) as count
                FROM `{project_id}.shift_data.app_interactions`
                WHERE user_id = @user_id
                  AND event_type = 'flow_requested'
                  AND JSON_EXTRACT_SCALAR(payload, '$.flow_id') = 'getting_started'
                  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
            """
            bq_client = bigquery.Client(project=project_id)
            job_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
                ]
            )
            query_job = bq_client.query(query, job_config=job_config)
            results = query_job.result()
            for row in results:
                flow_requested = row.count > 0
        except Exception as e:
            print(f"⚠️ Error checking flow_requested: {e}")
        
        if (not getting_started_completed or flow_requested):
            # Check if getting_started instance already exists
            existing_query = f"""
                SELECT COUNT(*) as count
                FROM `{project_id}.shift_data.intervention_instances`
                WHERE user_id = @user_id
                  AND intervention_key = 'getting_started_v1'
                  AND status = 'created'
            """
            try:
                job_config = bigquery.QueryJobConfig(
                    query_parameters=[
                        bigquery.ScalarQueryParameter("user_id", "STRING", user_id),
                    ]
                )
                query_job = bq_client.query(existing_query, job_config=job_config)
                results = query_job.result()
                instance_exists = False
                for row in results:
                    instance_exists = row.count > 0
                
                if not instance_exists:
                    # Create getting_started intervention instance on-demand
                    # Lazy import intervention selector modules
                    get_intervention_func, BigQueryClientClass = _get_intervention_selector_modules()
                    
                    if get_intervention_func and BigQueryClientClass:
                        selector_bq = BigQueryClientClass(project_id=project_id, dataset_id=dataset_id)
                        getting_started_catalog = get_intervention_func("getting_started_v1", selector_bq)
                    else:
                        getting_started_catalog = None
                        print("⚠️ Cannot create getting_started instance - intervention_selector modules not available")
                    
                    if getting_started_catalog:
                        trace_id = str(uuid4())
                        instance_id = selector_bq.create_intervention_instance(
                            user_id=user_id,
                            metric=getting_started_catalog.get("metric", "onboarding"),
                            level=getting_started_catalog.get("level", "default"),
                            surface=getting_started_catalog.get("surface", "chat_card"),
                            intervention_key="getting_started_v1",
                            trace_id=trace_id
                        )
                        print(f"✅ Created getting_started intervention instance {instance_id} for user {user_id}")
            except Exception as e:
                print(f"⚠️ Error creating getting_started instance: {e}")

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

        # PHASE 3: Conditionally insert getting_started intervention if not completed
        if not getting_started_completed:
            getting_started_dict = {
            "intervention_instance_id": str(uuid4()),
            "user_id": user_id,
            "metric": "getting_started",
            "level": "info",
            "surface": "notification",
            "intervention_key": "getting_started_v1",
            "title": "Welcome to SHIFT",
            "body": "Get started with your personal health operating system",
            "created_at": datetime.now().isoformat(),
            "scheduled_at": None,
            "sent_at": None,
            "status": "created",
            "trace_id": "getting-started-trace-id",
            "action": {
                "type": "full_screen_flow",
                "completion_action": {
                    "type": "chat_prompt",
                    "prompt": "The user is starting their GROW conversation. Begin with G (Goal)."
                }
            },
            "pages": [
                {
                    "template": "hero",
                    "title": "Welcome to SHIFT",
                    "subtitle": "Your personal health operating system"
                },
                {
                    "template": "feature_list",
                    "title": "Mind · Body · Bell",
                    "features": [
                        {
                            "icon": "brain.head.profile",
                            "title": "Mind",
                            "subtitle": "Track your mental wellness and cognitive patterns"
                        },
                        {
                            "icon": "figure.walk",
                            "title": "Body",
                            "subtitle": "Monitor your physical health and activity"
                        },
                        {
                            "icon": "bell",
                            "title": "Bell",
                            "subtitle": "Get timely insights and interventions"
                        }
                    ]
                },
                {
                    "template": "bullet_list",
                    "title": "How it works",
                    "bullets": [
                        "SHIFT continuously monitors your health data",
                        "Our AI identifies patterns and opportunities",
                        "You receive personalized interventions at the right time"
                    ]
                },
                {
                    "template": "cta",
                    "title": "Ready to begin?",
                    "button_text": "Start"
                }
            ]
            }
            interventions.insert(0, getting_started_dict)

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

        # Get saved interventions
        saved_intervention_keys = repo.get_saved_interventions(user_id=user_id)

        return {
            "state_estimate": state_payload,
            "interventions": interventions,
            "saved_interventions": saved_intervention_keys,
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Context endpoint error: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch context payload")


@app.post("/user/reset")
async def reset_user_data(
        request: ResetUserDataRequest,
        current_user: User = Depends(get_current_user)
):
    """Reset user data (for testing/control).
    
    Writes a flow_reset event to app_interactions.
    
    Body:
        {
            "scope": "all" | "flows" | "saved"  # optional, defaults to "all"
        }
    """
    print(f"🔍 [DEBUG] /user/reset endpoint REACHED - user_id: {current_user.user_id if current_user else 'None'}, scope: {request.scope if request else 'None'}")
    # #region agent log
    log_entry = {
        "location": "main.py:603",
        "message": "reset_user_data entry",
        "data": {"user_id": current_user.user_id if current_user else "None", "request_scope": request.scope if request else "None"},
        "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        "sessionId": "debug-session",
        "runId": "run1",
        "hypothesisId": "A"
    }
    print(f"🔍 [DEBUG] {json.dumps(log_entry)}")
    try:
        with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
            f.write(json.dumps(log_entry) + "\n")
    except Exception as e:
        print(f"⚠️ [DEBUG] Could not write log file: {e}")
    # #endregion
    
    try:
        scope = request.scope
        # #region agent log
        log_entry2 = {
            "location": "main.py:519",
            "message": "scope validation",
            "data": {"scope": scope, "is_valid": scope in ("all", "flows", "saved")},
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B"
        }
        try:
            with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
                f.write(json.dumps(log_entry2) + "\n")
        except Exception:
            pass
        # #endregion
        
        if scope not in ("all", "flows", "saved"):
            raise HTTPException(
                status_code=400,
                detail="scope must be 'all', 'flows', or 'saved'"
            )
        
        project_id = os.getenv("GCP_PROJECT_ID")
        
        # #region agent log
        log_entry3 = {
            "location": "main.py:526",
            "message": "project_id check",
            "data": {"project_id": project_id, "has_project_id": project_id is not None},
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "C"
        }
        try:
            with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
                f.write(json.dumps(log_entry3) + "\n")
        except Exception:
            pass
        # #endregion
        if not project_id:
            raise HTTPException(
                status_code=500,
                detail="GCP_PROJECT_ID not configured"
            )
        
        bq_client = bigquery.Client(project=project_id)
        table_id = f"{project_id}.shift_data.app_interactions"
        
        # Generate interaction_id and trace_id
        interaction_id = str(uuid4())
        trace_id = str(uuid4())  # New trace for reset event
        
        # Prepare payload
        payload = {"scope": scope}
        
        # Prepare row for insertion
        row_data = {
            "interaction_id": interaction_id,
            "trace_id": trace_id,
            "user_id": current_user.user_id,
            "intervention_instance_id": None,
            "event_type": "flow_reset",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "payload": json.dumps(payload)
        }
        
        rows_to_insert = [row_data]
        
        # #region agent log
        log_entry4 = {
            "location": "main.py:556",
            "message": "before BigQuery insert",
            "data": {"table_id": table_id, "interaction_id": interaction_id, "row_data_keys": list(row_data.keys())},
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "D"
        }
        try:
            with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
                f.write(json.dumps(log_entry4) + "\n")
        except Exception:
            pass
        # #endregion
        
        # Insert into BigQuery
        errors = bq_client.insert_rows_json(table_id, rows_to_insert)
        
        # #region agent log
        log_entry5 = {
            "location": "main.py:558",
            "message": "after BigQuery insert",
            "data": {"has_errors": errors is not None and len(errors) > 0, "error_count": len(errors) if errors else 0},
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "D"
        }
        try:
            with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
                f.write(json.dumps(log_entry5) + "\n")
        except Exception:
            pass
        # #endregion
        
        if errors:
            print(f"❌ BigQuery insert errors: {errors}")
            raise HTTPException(
                status_code=500,
                detail=f"Failed to store reset event: {errors}"
            )
        
        print(f"✅ Stored reset event: {interaction_id} for user {current_user.user_id}, scope={scope}")
        
        # #region agent log
        log_entry6 = {
            "location": "main.py:570",
            "message": "success response",
            "data": {"interaction_id": interaction_id, "scope": scope},
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "ALL"
        }
        try:
            with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
                f.write(json.dumps(log_entry6) + "\n")
        except Exception:
            pass
        # #endregion
        
        return {
            "message": "Reset event recorded",
            "scope": scope,
            "interaction_id": interaction_id
        }
        
    except HTTPException as e:
        # #region agent log
        log_entry_err = {
            "location": "main.py:573",
            "message": "HTTPException caught",
            "data": {"status_code": e.status_code, "detail": str(e.detail)},
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "E"
        }
        try:
            with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
                f.write(json.dumps(log_entry_err) + "\n")
        except Exception:
            pass
        # #endregion
        raise
    except Exception as e:
        # #region agent log
        log_entry_err2 = {
            "location": "main.py:576",
            "message": "unexpected exception",
            "data": {"error_type": type(e).__name__, "error_message": str(e)},
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "F"
        }
        try:
            with open("/Users/sly/dev/shift/.cursor/debug.log", "a") as f:
                f.write(json.dumps(log_entry_err2) + "\n")
        except Exception:
            pass
        # #endregion
        print(f"❌ Reset endpoint error: {e}")
        raise HTTPException(status_code=500, detail="Failed to process reset request")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
