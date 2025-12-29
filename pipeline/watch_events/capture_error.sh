#!/bin/bash
# Script to capture error details for debugging

BASE_URL="${1:-http://localhost:8080}"

echo "=========================================="
echo "Capturing error details for /user/reset"
echo "=========================================="
echo ""

echo "1. Testing health endpoint..."
curl -s "$BASE_URL/health" | jq . || echo "Health check failed"
echo ""

echo "2. Getting mock auth token..."
AUTH_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/apple/mock" \
  -H "Content-Type: application/json" \
  -d '{"identity_token":"test","authorization_code":"test"}')

TOKEN=$(echo "$AUTH_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id_token'])" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "❌ Failed to get auth token"
  echo "Response: $AUTH_RESPONSE"
  exit 1
fi

echo "✅ Got token: ${TOKEN:0:30}..."
echo ""

echo "3. Testing /user/reset endpoint..."
echo "-----------------------------------"
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}\nTIME:%{time_total}" -X POST "$BASE_URL/user/reset" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"scope": "all"}')

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d' | sed '/TIME:/d')

echo "HTTP Status: $HTTP_STATUS"
echo "Response Body:"
echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
echo ""

echo "4. Testing /debug/routes..."
curl -s "$BASE_URL/debug/routes" | python3 -m json.tool 2>/dev/null | grep -A 2 "user/reset" || echo "Route not found in debug output"
echo ""

echo "=========================================="
echo "Please copy the output above and share it"
echo "=========================================="

