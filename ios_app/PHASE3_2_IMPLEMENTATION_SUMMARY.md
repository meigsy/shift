# Phase 3.2 Implementation Summary

## Overview

Implemented agent-driven cards in the chat interface, replacing hardcoded debug UI with cards that the agent can send in response to events.

---

## Completed Changes

### 1. Removed Debug UI ✅

**Files Modified:**
- `ios_app/ios_app/ChatView.swift`
  - Removed debug toolbar buttons (lightning bolt, stress card, breathing card)
  - Removed debug helper functions

### 2. Created Agent Card Models ✅

**New Files:**
- `ios_app/ios_app/AgentCard.swift`
  - `AgentCard` struct: Represents cards sent from backend
  - `AgentCardAction` struct: Defines card actions (full_screen_flow, chat_prompt)
  - Codable implementation with proper JSON key mapping

### 3. Updated Chat Message System ✅

**Files Modified:**
- `ios_app/ios_app/ChatMessage.swift`
  - Added `textWithCard` case to `MessageKind` enum
  - Added initializer supporting text + optional `AgentCard`
  - Added `agentCard` computed property for easy access

- `ios_app/ios_app/ChatViewModel.swift`
  - Updated `injectMessage` to accept optional `card` parameter
  - Messages can now carry both text and agent cards

### 4. Created Card View Component ✅

**New Files:**
- `ios_app/ios_app/AgentCardView.swift`
  - SwiftUI view for rendering agent cards
  - Displays title, body, and action button
  - Dynamic button text based on action type
  - Consistent styling with shadow and rounded corners

### 5. Updated Chat Rendering ✅

**Files Modified:**
- `ios_app/ios_app/ChatMessageRow.swift`
  - Added `onAgentCardTap` callback parameter
  - Handles `textWithCard` case: renders text bubble + card below
  - Passes card tap events to parent view

- `ios_app/ios_app/ChatView.swift`
  - Added `showOnboarding` state
  - Added `handleAgentCardTap` function:
    - `full_screen_flow` → Shows onboarding sheet
    - `chat_prompt` → Sends card_tapped event
  - Added `makeToolEventService` helper
  - Added `.sheet` modifier for onboarding with flow_completed event

### 6. Updated ToolEventService ✅

**Files Modified:**
- `ios_app/ios_app/ToolEventService.swift`
  - Changed return type from `String?` to `(response: String?, card: AgentCard?)`
  - Parses `card` field from backend response
  - Automatically injects messages with cards into chat
  - Enhanced logging for card handling

### 7. Updated Backend ✅

**Files Modified:**
- `pipeline/conversational_agent/main.py`
  - Added `from user_context import get_user_context` import
  - Added card logic to `/tool_event` endpoint:
    - For `app_opened_first_time`: Check if user has profile name
    - If no name → Return "Welcome to SHIFT" card with getting_started flow
    - Card structure: `{type, title, body, action: {type, flow_id}}`

### 8. Wired Up App Lifecycle ✅

**Files Modified:**
- `ios_app/ios_app/AppShellView.swift`
  - Added `sendAppLaunchEvent` function:
    - Determines first launch vs subsequent launch
    - Sends `app_opened_first_time` or `app_opened` event
    - Injects response + card into chat
    - Sets `has_launched_before` UserDefaults flag
  - Called from `.task` modifier on app start

---

## How It Works

### First Launch Flow
1. App starts → `AppShellView.sendAppLaunchEvent()` runs
2. Checks UserDefaults: `has_launched_before` = false
3. Sends `app_opened_first_time` event to backend
4. Backend checks user_context: no profile name found
5. Backend returns:
   ```json
   {
     "status": "ok",
     "response": "Welcome! Let me show you how SHIFT works...",
     "card": {
       "type": "getting_started",
       "title": "Welcome to SHIFT",
       "body": "Learn how SHIFT works in 60 seconds",
       "action": {
         "type": "full_screen_flow",
         "flow_id": "getting_started"
       }
     }
   }
   ```
6. iOS injects message with card into chat
7. User sees greeting text + card in chat
8. User taps card → Onboarding slideshow opens
9. User taps "Start" → `flow_completed` event sent
10. Slideshow dismisses

### Subsequent Launch Flow
1. App starts → `AppShellView.sendAppLaunchEvent()` runs
2. Checks UserDefaults: `has_launched_before` = true
3. Sends `app_opened` event to backend
4. Backend returns greeting (no card)
5. iOS injects message into chat
6. Chat continues from previous state

---

## Testing Instructions

### Build Test
```bash
cd ios_app
xcodebuild -scheme ios_app -project ios_app.xcodeproj build
```

### Manual Test - First Launch
1. Delete app from simulator (to reset UserDefaults)
2. Run app
3. **Expected:**
   - Agent greeting appears in chat
   - "Welcome to SHIFT" card appears below greeting
   - Card has blue button "Learn More"
4. Tap card
5. **Expected:**
   - Onboarding slideshow opens (4 pages)
6. Swipe to last page, tap "Start"
7. **Expected:**
   - `flow_completed` event sent (check console logs)
   - Slideshow dismisses
   - Chat remains with greeting + card

### Manual Test - Subsequent Launch
1. Close and reopen app (don't delete)
2. **Expected:**
   - Agent greeting appears (no card)
   - Previous messages still visible

### Verify Logs
Look for:
- `📱 Sending app launch event: app_opened_first_time`
- `📇 Card parsed: Welcome to SHIFT`
- `💬 Agent response injected into chat`
- `🎯 Agent card tapped: Welcome to SHIFT`
- `✅ Tool event sent successfully`

---

## Architecture Decisions

### Card Ownership
- **Backend decides:** Agent logic determines when to show cards
- **iOS renders:** Views parse and display cards sent from backend
- **Simple MVP:** Only `getting_started` card implemented

### Thread Continuity
- All tool events use `chatViewModel.activeThreadId`
- Cards appear in same conversation as user messages
- Agent maintains context across events and chat

### Event Flow
```
iOS Event → ToolEventService → Backend Agent → Response + Optional Card → ChatViewModel → ChatView Render
```

### Backward Compatibility
- Existing chat messages unchanged (text-only)
- Legacy `ChatCard` system still works
- New `AgentCard` system is additive

---

## Files Created
1. `ios_app/ios_app/AgentCard.swift`
2. `ios_app/ios_app/AgentCardView.swift`
3. `ios_app/PHASE3_2_IMPLEMENTATION_SUMMARY.md` (this file)

## Files Modified
1. `ios_app/ios_app/ChatView.swift`
2. `ios_app/ios_app/ChatMessage.swift`
3. `ios_app/ios_app/ChatMessageRow.swift`
4. `ios_app/ios_app/ChatViewModel.swift`
5. `ios_app/ios_app/ToolEventService.swift`
6. `ios_app/ios_app/AppShellView.swift`
7. `pipeline/conversational_agent/main.py`

---

## Next Steps (Phase 4)

### Potential Improvements
1. **More Card Types:** Intervention cards, check-in cards, rating cards
2. **Card Persistence:** Save cards in message history across sessions
3. **Card Dismissal:** Allow user to dismiss cards without tapping
4. **Card Analytics:** Track card impression/tap rates
5. **Rich Card Content:** Support images, lists, custom layouts

### Open Questions
1. Should cards be dismissable separately from messages?
2. Should cards persist across app restarts?
3. Should we show multiple cards at once or queue them?
4. How should card re-appearance work (e.g., if user closes without tapping)?

---

## Phase 3.2 Success Criteria

- ✅ Debug UI removed (lightning bolt, About SHIFT)
- ✅ Cards render in chat
- ✅ Card tap launches slideshow
- ✅ flow_completed event sent
- ✅ First launch vs subsequent launch handled correctly
- ✅ No regression in existing chat functionality
- ✅ Backend returns cards conditionally
- ✅ Thread ID continuity maintained

All success criteria met! Ready for user testing.

