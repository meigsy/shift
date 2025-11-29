# SHIFT Backend API

FastAPI backend service for SHIFT fitness OS, handling authentication and health data ingestion.

## Overview

The backend provides:
- Sign in with Apple authentication via GCP Identity Platform
- User management
- Health data ingestion from iOS app
- Token verification and authorization

## Endpoints

### `GET /health`
Health check endpoint.

**Response:**
```json
{
  "status": "ok"
}
```

### `POST /auth/apple`
Authenticate with Sign in with Apple.

**Request Body:**
```json
{
  "identity_token": "JWT from Apple",
  "authorization_code": "Authorization code from Apple"
}
```

**Response:**
```json
{
  "id_token": "Identity Platform JWT",
  "refresh_token": "Refresh token (optional)",
  "expires_in": 3600,
  "user": {
    "user_id": "user-id",
    "email": "user@example.com",
    "display_name": "User Name",
    "created_at": "2025-11-25T12:00:00Z"
  }
}
```

### `GET /me`
Get current authenticated user information.

**Headers:**
- `Authorization: Bearer <id_token>`

**Response:**
```json
{
  "user_id": "user-id",
  "email": "user@example.com",
  "display_name": "User Name",
  "created_at": "2025-11-25T12:00:00Z"
}
```

### `POST /watch_events`
Receive health data batch from iOS app.

**Headers:**
- `Authorization: Bearer <id_token>`

**Request Body:**
See `schemas.py` for `HealthDataBatch` structure.

**Response:**
```json
{
  "message": "Health data received",
  "samples_received": 150,
  "user_id": "user-id"
}
```

## Environment Variables

Required environment variables:

- `GCP_PROJECT_ID` - GCP project ID
- `IDENTITY_PLATFORM_PROJECT_ID` - Identity Platform project ID (can be same as GCP_PROJECT_ID)
- `IDENTITY_PLATFORM_API_KEY` - API key for Identity Platform REST API
- `APPLE_CLIENT_ID` - Apple Service ID (Client ID)
- `APPLE_KEY_ID` - Apple Key ID (optional, for future use)
- `APPLE_TEAM_ID` - Apple Team ID (optional, for future use)
- `APPLE_PRIVATE_KEY_SECRET_ID` - Secret Manager secret ID for Apple private key (optional)

## Local Development

### Prerequisites

- Python 3.11+
- [uv](https://github.com/astral-sh/uv) (fast Python package installer)

### Setup

1. Install dependencies:
```bash
cd backend
uv sync
```

2. Set environment variables:
```bash
export GCP_PROJECT_ID="shift-dev"
export IDENTITY_PLATFORM_PROJECT_ID="shift-dev"
export IDENTITY_PLATFORM_API_KEY="your-api-key"
export APPLE_CLIENT_ID="com.shift.ios-app"
```

3. Run the server:
```bash
uv run uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

The API will be available at `http://localhost:8080`

### Testing

Test the health endpoint:
```bash
curl http://localhost:8080/health
```

Test authenticated endpoint (requires valid token):
```bash
curl -H "Authorization: Bearer <id_token>" http://localhost:8080/me
```

Run test scripts:
```bash
uv run python test_mock_auth.py
uv run python test_identity_platform_token.py
```

## Docker Deployment

### Build Image

```bash
docker build -t shift-backend:latest .
```

### Run Container

```bash
docker run -p 8080:8080 \
  -e GCP_PROJECT_ID=shift-dev \
  -e IDENTITY_PLATFORM_API_KEY=your-api-key \
  -e APPLE_CLIENT_ID=com.shift.ios-app \
  shift-backend:latest
```

**Note**: For local development, prefer using `uv` instead of Docker for faster iteration.

### Deploy to Cloud Run

```bash
# Tag image
docker tag shift-backend:latest gcr.io/shift-dev/shift-backend:latest

# Push to GCR
docker push gcr.io/shift-dev/shift-backend:latest

# Deploy (or use Terraform)
gcloud run deploy shift-backend \
  --image gcr.io/shift-dev/shift-backend:latest \
  --platform managed \
  --region us-central1 \
  --project shift-dev
```

## Architecture

### Authentication Flow

1. iOS app performs Sign in with Apple
2. iOS sends `identity_token` and `authorization_code` to `/auth/apple`
3. Backend verifies Apple token using Apple's JWKS
4. Backend exchanges credentials with Identity Platform `signInWithIdp` API
5. Backend returns Identity Platform `id_token` to iOS
6. iOS uses `id_token` for authenticated requests

### Token Verification

- Apple tokens verified using Apple's public JWKS
- Identity Platform tokens verified using Google's public JWKS
- Tokens cached for performance

### User Storage

Currently uses in-memory storage (`users_repo.py`). Designed to be swapped for database (Firestore, PostgreSQL, etc.) later.

## Error Handling

- `400 Bad Request` - Invalid request format
- `401 Unauthorized` - Missing or invalid token
- `404 Not Found` - Resource not found
- `500 Internal Server Error` - Server error

All errors return JSON:
```json
{
  "detail": "Error message"
}
```

## Security Notes

- All sensitive values should be in Secret Manager or environment variables
- Tokens are verified using public key cryptography
- CORS is currently open (`*`) - restrict in production
- Cloud Run service is publicly accessible - auth handled in application


