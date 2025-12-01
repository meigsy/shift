# Testing Guide

This guide covers testing the SHIFT auth slice with what we have available, without requiring a full Apple Developer account setup.

## Quick Start

### 1. Backend Testing (No Account Needed)

Test the backend endpoints independently:

```bash
# Start the backend
cd backend
uv sync
uv run uvicorn main:app --reload

# In another terminal, run the test script
cd backend
uv run python test_mock_auth.py
```

This will test:
- `/health` endpoint
- `/auth/apple/mock` endpoint (mock authentication)
- `/me` endpoint (will show 401 with mock tokens - expected)
- `/watch_events` endpoint (will show 401 with mock tokens - expected)

### 2. iOS App Testing (Simulator + Mock Backend)

Test the iOS app flow with the mock backend:

1. **Start the backend** (from step 1 above)

2. **Update iOS app configuration**:
   - The app is already configured to use mock auth by default
   - Backend URL is set to `http://localhost:8080`
   - If your backend is on a different machine, update `ios_appApp.swift`:
     ```swift
     @StateObject private var authViewModel = AuthViewModel(
         backendBaseURL: "http://YOUR_IP:8080",  // Your computer's IP
         useMockAuth: true
     )
     ```

3. **Run iOS app in simulator**:
   ```bash
   # Open Xcode
   open ios_app/ios_app.xcodeproj
   
   # Select a simulator (iPhone 15 Pro recommended)
   # Build and run (Cmd+R)
   ```

4. **Test the flow**:
   - App shows login screen
   - Tap "Continue with Apple"
   - Sign in with Apple (works in simulator with free Apple ID)
   - App receives mock token from backend
   - App shows MainView with user info

**Note**: The `/me` and `/watch_events` endpoints will return 401 because mock tokens aren't real JWTs. This is expected. The important part is testing the iOS app flow.

## Testing Scenarios

### Scenario 1: Backend Health Check

```bash
curl http://localhost:8080/health
```

Expected: `{"status":"ok"}`

### Scenario 2: Mock Authentication

```bash
curl -X POST http://localhost:8080/auth/apple/mock \
  -H "Content-Type: application/json" \
  -d '{
    "identity_token": "test.token.123",
    "authorization_code": "test.code.456"
  }'
```

Expected: Returns mock user and token

### Scenario 3: iOS App → Backend Flow

1. Start backend: `uvicorn main:app --reload`
2. Run iOS app in simulator
3. Tap "Continue with Apple"
4. Complete Sign in with Apple
5. Check backend logs - you should see:
   - POST request to `/auth/apple/mock`
   - Response with mock token

### Scenario 4: Health Data Sync (Partial)

The health data sync will work up to the point of sending data, but `/watch_events` will return 401 because the mock token isn't verified. This is expected.

To test the full flow, you need:
- Real Identity Platform tokens (requires Apple Developer account)
- Or modify the backend to accept mock tokens for `/me` and `/watch_events` (not recommended for production)

## Limitations Without Apple Developer Account

### What Works ✅

- Backend endpoints (health, mock auth)
- iOS app UI and navigation
- Sign in with Apple flow in simulator
- Mock token generation and storage
- Basic app flow (login → authenticated state)

### What Doesn't Work ❌

- Real Identity Platform token verification
- `/me` endpoint with mock tokens (returns 401)
- `/watch_events` endpoint with mock tokens (returns 401)
- Full end-to-end health data sync

### Why Mock Tokens Fail Verification

Mock tokens are just random strings, not real JWTs. The Identity Platform token verification in `auth_identity_platform.py` expects:
- Valid JWT structure
- Valid signature from Google
- Valid claims (iss, aud, exp, etc.)

## Testing with Real Tokens (Requires Apple Developer Account)

Once you have an Apple Developer account:

1. **Configure Apple Service ID**:
   - Apple Developer Portal → Certificates, Identifiers & Profiles
   - Create Service ID: `com.shift.ios-app`
   - Enable Sign in with Apple
   - Configure return URL: `https://YOUR_PROJECT_ID.firebaseapp.com/__/auth/handler`

2. **Configure Identity Platform**:
   - GCP Console → Identity Platform
   - Add Apple as OIDC provider
   - Use Service ID as Client ID

3. **Update iOS app**:
   ```swift
   @StateObject private var authViewModel = AuthViewModel(
       backendBaseURL: "https://your-cloud-run-url.run.app",
       useMockAuth: false  // Use real auth
   )
   ```

4. **Test full flow**:
   - Sign in with Apple → Real tokens → Full verification → Health data sync

## Troubleshooting

### Backend won't start

```bash
# Check if uv is installed
uv --version

# Install dependencies
cd backend
uv sync

# Check if port 8080 is available
lsof -i :8080
```

### iOS app can't connect to backend

- **If using localhost**: iOS simulator can access `localhost` directly
- **If using physical device**: Use your computer's IP address:
  ```swift
  backendBaseURL: "http://192.168.1.XXX:8080"  // Your computer's IP
  ```
- **Check firewall**: Make sure port 8080 is not blocked

### Sign in with Apple not working in simulator

- Make sure you're signed into iCloud in simulator
- Settings → Sign in to your iPhone → Use your Apple ID
- Try a different simulator if issues persist

### Mock tokens return 401

This is expected! Mock tokens are not real JWTs, so they fail Identity Platform verification. This is normal for testing without an Apple Developer account.

## Next Steps

1. ✅ Test backend endpoints with mock auth
2. ✅ Test iOS app flow with mock backend
3. ⏳ Get Apple Developer account (when ready)
4. ⏳ Configure Service ID and Identity Platform
5. ⏳ Test full end-to-end flow

## Additional Test Scripts

### Test Identity Platform Token Verification

If you have a real Identity Platform token:

```bash
cd backend
export TEST_ID_TOKEN="your-real-token-here"
export GCP_PROJECT_ID="shift-dev"
uv run python test_identity_platform_token.py
```

### Manual API Testing

Use the test scripts in `pipeline/watch_events/`:
- `test_mock_auth.py` - Test mock authentication flow
- `test_identity_platform_token.py` - Test token verification

Or use curl/Postman to test endpoints manually.

