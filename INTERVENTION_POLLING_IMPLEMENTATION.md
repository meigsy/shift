# Intervention Polling Implementation - Complete

## ✅ What's Been Implemented

### Backend

1. **List Endpoint** (`pipeline/intervention_selector/main.py`)
   - `GET /interventions?user_id={user_id}&status={status}` - Returns array of interventions
   - Supports existing `GET /interventions/{id}` for single intervention lookup
   - Query parameters: `user_id` (required), `status` (optional, default: "created")

2. **BigQuery Query Method** (`pipeline/intervention_selector/src/bigquery_client.py`)
   - `get_interventions_for_user()` - Queries intervention_instances table
   - Filters by user_id and status
   - Merges with catalog to include title/body
   - Returns list of intervention dicts

3. **Deployed**
   - Cloud Function updated: `intervention-selector-http`
   - URL: `https://us-central1-shift-dev-478422.cloudfunctions.net/intervention-selector-http`

### iOS App

1. **Intervention.swift** - Data model
   - Decodable struct matching backend JSON
   - Handles ISO8601 date parsing (multiple formats)
   - Identifiable for SwiftUI

2. **InterventionService.swift** - API client
   - Fetches pending interventions from backend
   - Uses ApiClient for authenticated requests

3. **InterventionBanner.swift** - UI component
   - Banner/toast style notification
   - Auto-dismisses after 8 seconds
   - Swipe-up to dismiss
   - Color-coded by level (high=orange, medium=blue, low=green)

4. **InterventionRouter.swift** - Surface routing
   - Routes interventions by `surface` field
   - "notification" → shows banner
   - Future: "in_app" → shows card (stub ready)

5. **InterventionPoller.swift** - Polling service
   - Polls every 60 seconds when app is active
   - Tracks seen interventions to avoid duplicates
   - Starts/stops based on app lifecycle

6. **MainView.swift** - Integration
   - Initializes polling when user is authenticated
   - Displays banners via overlay
   - Handles foreground/background transitions

## 📋 Next Steps

### 1. Add iOS Files to Xcode Project

The following new files need to be added to your Xcode project:

```
ios_app/ios_app/
├── Intervention.swift
├── InterventionService.swift
├── InterventionBanner.swift
├── InterventionRouter.swift
└── InterventionPoller.swift
```

**How to add:**
1. Open `ios_app.xcodeproj` in Xcode
2. Right-click on `ios_app` folder in Project Navigator
3. Select "Add Files to ios_app..."
4. Select all 5 new Swift files
5. Ensure "Copy items if needed" is unchecked (files are already in place)
6. Ensure "Add to targets: ios_app" is checked
7. Click "Add"

### 2. Configure Intervention Base URL

Update the intervention base URL in `MainView.swift` if needed:

```swift
@State private var interventionBaseURL: String = "https://us-central1-shift-dev-478422.cloudfunctions.net/intervention-selector-http"
```

Currently hardcoded. Consider making it configurable via environment or AuthViewModel.

### 3. Test End-to-End

1. **Create test intervention:**
   - Run `./test_pipeline.sh` to create a high-stress state estimate
   - Verify intervention instance is created in BigQuery

2. **Test iOS polling:**
   - Build and run iOS app
   - Sign in with mock auth
   - Wait 60 seconds (or trigger manually in debugger)
   - Verify banner appears with intervention

### 4. Verify Backend List Endpoint

Test with curl:
```bash
curl "https://us-central1-shift-dev-478422.cloudfunctions.net/intervention-selector-http/interventions?user_id=YOUR_USER_ID&status=created"
```

## 🧪 Testing Checklist

- [ ] Backend list endpoint returns empty array for user with no interventions
- [ ] Backend list endpoint returns interventions for user with pending interventions
- [ ] iOS app polls successfully when authenticated
- [ ] iOS app shows banner for "notification" surface
- [ ] Banner auto-dismisses after 8 seconds
- [ ] Banner can be swiped to dismiss
- [ ] Polling stops when app backgrounds
- [ ] Polling resumes when app foregrounds
- [ ] No duplicate banners for same intervention

## 🔗 Endpoint URLs

- **List Interventions**: `https://us-central1-shift-dev-478422.cloudfunctions.net/intervention-selector-http/interventions?user_id={user_id}&status=created`
- **Single Intervention**: `https://us-central1-shift-dev-478422.cloudfunctions.net/intervention-selector-http/interventions/{intervention_instance_id}`

## 📊 Current Flow

```
State Estimator → state_estimates table → Pub/Sub message
  ↓
Intervention Selector → intervention_instances table (status: "created")
  ↓
iOS App polls every 60s → GET /interventions?user_id=X&status=created
  ↓
InterventionRouter → checks surface → shows banner for "notification"
  ↓
User sees intervention banner in app
```

## 🚀 Future Enhancements

- Push notifications (APNs) for real-time delivery
- "in_app" surface implementation (cards in MainView)
- Intervention interaction tracking (completed/snoozed/dismissed)
- User preferences for intervention timing/frequency

