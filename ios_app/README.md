# SHIFT iOS App

Native iOS app for SHIFT fitness OS with Sign in with Apple authentication and HealthKit integration.

## Overview

The iOS app provides:
- Sign in with Apple authentication
- HealthKit data ingestion
- Background health data sync
- Authenticated API communication

## Setup

### Prerequisites

- Xcode 15+
- iOS 17+ deployment target
- Apple Developer account
- Sign in with Apple capability enabled

### Configuration

1. **Sign in with Apple Setup**:
   - In Apple Developer Portal, create a Service ID
   - Configure return URLs for Identity Platform
   - Enable Sign in with Apple capability in Xcode

2. **Backend URL Configuration**:
   - Update `AuthViewModel` initialization in `ios_appApp.swift`:
   ```swift
   AuthViewModel(backendBaseURL: "https://your-cloud-run-url.run.app")
   ```

3. **Bundle ID**:
   - Must match Apple Service ID configuration
   - Current: `com.shift.ios-app`

### Capabilities

The app requires these capabilities (configured in `ios_app.entitlements`):
- HealthKit
- HealthKit Background Delivery
- Sign in with Apple

## Architecture

### Authentication Flow

1. User taps "Continue with Apple" in `LoginView`
2. `AuthViewModel` handles Sign in with Apple flow
3. Apple returns `identityToken` and `authorizationCode`
4. `AuthViewModel` sends credentials to backend `/auth/apple`
5. Backend returns Identity Platform `id_token`
6. Token stored in UserDefaults and memory
7. App shows `MainView` with authenticated state

### Health Data Sync

1. `HealthKitManager` fetches health data
2. `SyncService` uses `ApiClient` to POST to `/watch_events`
3. `ApiClient` includes `Authorization: Bearer <id_token>` header
4. Backend verifies token and associates data with user

### Key Components

- **AuthViewModel**: Manages authentication state and Sign in with Apple
- **ApiClient**: Handles authenticated HTTP requests
- **SyncService**: Syncs health data to backend
- **HealthKitManager**: Manages HealthKit access and data fetching

## Running the App

1. Open `ios_app.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on simulator or device
4. Sign in with Apple (requires device or simulator with Apple ID)

## Testing

### Sign in Flow

1. Launch app
2. Tap "Continue with Apple"
3. Complete Sign in with Apple
4. Verify user info appears in `MainView`

### Health Data Sync

1. Ensure HealthKit is authorized
2. Wait for background sync or manually trigger
3. Check backend logs for `/watch_events` requests
4. Verify data is associated with authenticated user

## Environment Configuration

For different environments (dev/prod), update the backend URL:

```swift
// Development
AuthViewModel(backendBaseURL: "https://shift-backend-dev.run.app")

// Production
AuthViewModel(backendBaseURL: "https://shift-backend-prod.run.app")
```

Consider using build configurations or Info.plist for environment-specific URLs.

## Token Management

- Tokens stored in UserDefaults for persistence
- Tokens automatically included in API requests via `ApiClient`
- On 401 Unauthorized, user is signed out and must re-authenticate
- Token refresh not yet implemented (future enhancement)

## Background Sync

The app observes HealthKit updates and syncs data in the background:
- Uses background tasks for sync operations
- Syncs only new data since last sync timestamp
- Handles network errors gracefully

## Troubleshooting

### Sign in with Apple Not Working

- Verify Sign in with Apple capability is enabled
- Check bundle ID matches Apple Service ID
- Ensure Apple Developer account is configured
- Test on physical device (simulator may have limitations)

### Health Data Not Syncing

- Verify HealthKit authorization is granted
- Check backend URL is correct
- Ensure user is authenticated
- Check network connectivity
- Review console logs for errors

### Token Expired

- User will be signed out automatically
- Must sign in again to get new token
- Token expiration handled by backend verification

## Future Enhancements

- Token refresh mechanism
- Keychain storage for tokens (more secure than UserDefaults)
- Offline queue for health data
- Push notification support
- Error retry logic







