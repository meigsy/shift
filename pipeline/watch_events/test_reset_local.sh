#!/bin/bash
# Test script for /user/reset endpoint locally
# Run this after starting the local server with: ./start_test_server.sh

set -e

BASE_URL="http://localhost:8080"

echo "Testing /user/reset endpoint locally"
echo "======================================"
echo ""

# Step 1: Get mock auth token
echo "1. Getting mock auth token..."
AUTH_RESPONSE=$(curl -s -X POST "${BASE_URL}/auth/apple/mock" \
  -H "Content-Type: application/json" \
  -d '{"identity_token":"test","authorization_code":"test"}')

TOKEN=$(echo "$AUTH_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id_token'])" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
  echo "❌ Failed to get auth token"
  echo "Response: $AUTH_RESPONSE"
  exit 1
fi

echo "✅ Got token: ${TOKEN:0:20}..."
echo ""

# Step 2: Test /user/reset endpoint
echo "2. Testing /user/reset with scope='all'..."
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "${BASE_URL}/user/reset" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"scope": "all"}')

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo "HTTP Status: $HTTP_STATUS"
echo "Response Body: $BODY"
echo ""

if [ "$HTTP_STATUS" = "200" ]; then
  echo "✅ SUCCESS: Endpoint works correctly!"
  echo ""
  echo "The Pydantic model fix resolves the issue."
  echo "The endpoint should work after deployment."
else
  echo "❌ FAILED: Got status $HTTP_STATUS"
  echo ""
  if [ "$HTTP_STATUS" = "404" ]; then
    echo "This might mean:"
    echo "  - Server isn't running (check with: curl ${BASE_URL}/health)"
    echo "  - Route isn't registered (check server logs)"
  elif [ "$HTTP_STATUS" = "422" ]; then
    echo "This might mean the request body parsing failed."
  elif [ "$HTTP_STATUS" = "401" ]; then
    echo "This might mean auth token wasn't accepted."
  fi
  exit 1
fi

