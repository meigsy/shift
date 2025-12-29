#!/bin/bash
# Complete test script for /user/reset endpoint

set -e

BASE_URL="${1:-http://localhost:8080}"

echo "=========================================="
echo "Testing /user/reset endpoint"
echo "Server: $BASE_URL"
echo "=========================================="
echo ""

echo "1. Testing health endpoint..."
if curl -s "$BASE_URL/health" > /dev/null; then
    echo "   ✅ Server is reachable"
else
    echo "   ❌ Server is not reachable at $BASE_URL"
    echo "   Make sure the server is running"
    exit 1
fi
echo ""

echo "2. Getting mock auth token..."
AUTH_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/apple/mock" \
  -H "Content-Type: application/json" \
  -d '{"identity_token":"test","authorization_code":"test"}')

if echo "$AUTH_RESPONSE" | python3 -c "import sys, json; json.load(sys.stdin)" > /dev/null 2>&1; then
    TOKEN=$(echo "$AUTH_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id_token'])")
    echo "   ✅ Got token: ${TOKEN:0:30}..."
else
    echo "   ❌ Failed to get auth token"
    echo "   Response: $AUTH_RESPONSE"
    exit 1
fi
echo ""

echo "3. Testing /user/reset endpoint..."
echo "-----------------------------------"
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$BASE_URL/user/reset" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"scope": "all"}')

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo "HTTP Status: $HTTP_STATUS"
echo "Response Body:"
echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
echo ""

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ SUCCESS! Endpoint works correctly."
    exit 0
elif [ "$HTTP_STATUS" = "404" ]; then
    echo "❌ 404 NOT FOUND"
    echo "   - Route might not be registered"
    echo "   - Check server logs for route registration"
    echo "   - Make sure code changes were deployed/restarted"
    exit 1
elif [ "$HTTP_STATUS" = "422" ]; then
    echo "❌ 422 VALIDATION ERROR"
    echo "   - Request body parsing failed"
    echo "   - Check the 'detail' field above for validation errors"
    exit 1
elif [ "$HTTP_STATUS" = "401" ]; then
    echo "❌ 401 UNAUTHORIZED"
    echo "   - Authentication failed"
    exit 1
elif [ "$HTTP_STATUS" = "500" ]; then
    echo "❌ 500 SERVER ERROR"
    echo "   - Check server logs for details"
    exit 1
else
    echo "⚠️ Unexpected status: $HTTP_STATUS"
    exit 1
fi

