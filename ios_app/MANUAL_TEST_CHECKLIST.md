# Manual Test Checklist - iOS Chat UI (Phase 1)

## 1. App Launch & Navigation
- [ ] App launches to AppShellView (not MainView) when authenticated
- [ ] LoginView shows when not authenticated
- [ ] Can access MainView/HomeView via escape hatch: Set `useChatShell` to `false` in UserDefaults or via debug toggle

## 2. Side Panel
- [ ] Side panel slides in from left when hamburger menu button is tapped
- [ ] Background dims when side panel is open
- [ ] Tap outside closes side panel
- [ ] Swipe-to-close works (swipe left on panel)

## 3. Chat Functionality
- [ ] Empty state displays when no messages ("Start a conversation" message)
- [ ] Can send a message via input field
- [ ] SSE streaming displays correctly (message appears incrementally as chunks arrive)
- [ ] Multiple messages can be sent and received
- [ ] Auth token is passed correctly to chat service (no 401 errors)
- [ ] Messages scroll to bottom automatically when new messages arrive

## 4. New Chat Action
- [ ] "New Chat" button in side panel clears messages
- [ ] "New Chat" creates new thread ID: `user_\(userId)_thread_\(UUID())`
- [ ] After "New Chat", can start fresh conversation
- [ ] Side panel closes after "New Chat" is tapped

## 5. Side Panel Menu
- [ ] "Past Chats" section visible (placeholder "Coming soon" OK)
- [ ] "User Menu" shows Settings (placeholder) and Logout
- [ ] Logout button calls `AuthViewModel.signOut()` correctly
- [ ] After logout, app returns to LoginView

## 6. Thread Management
- [ ] Default thread ID `"user_\(userId)_active"` works correctly
- [ ] New chat creates explicit thread ID `"user_\(userId)_thread_\(UUID())"`
- [ ] Thread IDs are always explicit strings (no nil)
- [ ] userId sourced from `authViewModel.user?.userId` (fallback to "debug-user" in DEBUG)

## 7. Message Model
- [ ] ChatMessage model has id, role, text, createdAt
- [ ] Messages render correctly in ChatView
- [ ] User messages appear on right (blue), assistant on left (gray)
- [ ] Streaming updates message text incrementally

## 8. SSE Parsing
- [ ] Only `data:` lines are parsed
- [ ] Non-`data:` lines are ignored
- [ ] Empty `data:` lines are no-op
- [ ] Terminal marker `[DONE]` ends stream correctly
- [ ] Loading indicator shows while streaming
- [ ] Loading indicator disappears when stream completes

## 9. Error Handling
- [ ] Network errors display error message below input field
- [ ] Invalid URL errors are handled gracefully
- [ ] HTTP errors (4xx, 5xx) display appropriate error messages
- [ ] Failed messages are removed from UI (assistant message with error)

## 10. Main Actor / Threading
- [ ] All UI updates occur on main thread (no crashes or warnings)
- [ ] Streaming updates don't block UI
- [ ] Side panel animations are smooth
- [ ] Message list scrolling is smooth

## Notes
- **Base URL Configuration**: Add `CONVERSATIONAL_AGENT_BASE_URL` to Info.plist:
  - In Xcode: Target → Info → Custom iOS Target Properties → Add `CONVERSATIONAL_AGENT_BASE_URL` key with deployed URL value
  - Or add to build settings: `INFOPLIST_KEY_CONVERSATIONAL_AGENT_BASE_URL = "https://conversational-agent-xxx-uc.a.run.app"`
  - Falls back to placeholder in DEBUG builds if not set
- **Escape hatch**: Use `@AppStorage("useChatShell")` - can toggle via UserDefaults or debug menu
- **MainView/HomeView**: Preserved and accessible via escape hatch toggle

