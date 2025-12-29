# /user/reset Endpoint Fix Summary

## Problem
The `/user/reset` endpoint was using `Dict[str, Any]` for the request body, which FastAPI doesn't parse correctly without explicit `Body()`, causing 404/422 errors.

## Solution
Changed from:
```python
@app.post("/user/reset")
async def reset_user_data(
        request: Dict[str, Any],  # ❌ Doesn't work
        current_user: User = Depends(get_current_user)
):
```

To:
```python
@app.post("/user/reset")
async def reset_user_data(
        request: ResetUserDataRequest,  # ✅ Works - Pydantic model
        current_user: User = Depends(get_current_user)
):
```

## Verification

### 1. Code Check
- ✅ File: `pipeline/watch_events/main.py` line 630-634
- ✅ Uses `ResetUserDataRequest` Pydantic model
- ✅ Follows same pattern as `/app_interactions` and `/watch_events` endpoints
- ✅ Code compiles without errors

### 2. Pydantic Model
- ✅ File: `pipeline/watch_events/schemas.py` line 104-106
- ✅ Model defined: `ResetUserDataRequest` with `scope: str = Field(default="all")`

### 3. Testing Steps

**Local Test:**
```bash
cd /Users/sly/dev/shift/pipeline/watch_events
export GCP_PROJECT_ID=shift-dev-478422
uv run uvicorn main:app --host 127.0.0.1 --port 8080 --reload
```

**In another terminal:**
```bash
# Get mock token
TOKEN=$(curl -s -X POST "http://localhost:8080/auth/apple/mock" \
  -H "Content-Type: application/json" \
  -d '{"identity_token":"test","authorization_code":"test"}' | \
  python3 -c "import sys, json; print(json.load(sys.stdin)['id_token'])")

# Test endpoint
curl -v -X POST "http://localhost:8080/user/reset" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"scope": "all"}'
```

**Expected:** HTTP 200 with:
```json
{
  "message": "Reset event recorded",
  "scope": "all",
  "interaction_id": "..."
}
```

## If Still Getting Errors

Please share:
1. HTTP status code (404, 422, 500, etc.)
2. Full error message/response body
3. Server console output (especially `🔍 [DEBUG]` lines)
4. Whether testing locally or against deployed endpoint

## Deployment

After local testing succeeds, deploy:
```bash
cd /Users/sly/dev/shift
./deploy.sh
```

