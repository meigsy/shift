#!/bin/bash
# Quick start script for testing the backend

echo "Starting SHIFT Backend Test Server..."
echo "======================================"
echo ""

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "Error: uv is not installed. Install it from https://github.com/astral-sh/uv"
    exit 1
fi

# Sync dependencies
echo "Installing dependencies with uv..."
uv sync

# Set default environment variables if not set
export GCP_PROJECT_ID=${GCP_PROJECT_ID:-"shift-dev"}
export IDENTITY_PLATFORM_PROJECT_ID=${IDENTITY_PLATFORM_PROJECT_ID:-"shift-dev"}

echo ""
echo "Starting server on http://localhost:8080"
echo "Press Ctrl+C to stop"
echo ""
echo "Test endpoints:"
echo "  - Health: curl http://localhost:8080/health"
echo "  - Mock Auth: curl -X POST http://localhost:8080/auth/apple/mock -H 'Content-Type: application/json' -d '{\"identity_token\":\"test\",\"authorization_code\":\"test\"}'"
echo ""

# Start the server
uv run uvicorn main:app --host 0.0.0.0 --port 8080 --reload

