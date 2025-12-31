# SHIFT Agent Architecture - Implementation Guide

**Document Version:** 3.0  
**Last Updated:** 2025-12-31  
**Status:** Phases 0-2 Complete & Deployed, Phase 3 In Progress

---

## Current Status

### ✅ Completed & Deployed

**Phase 0 (Foundation):**
- Tools: `update_user_context`, `send_notification` (stubs with logging)
- Middleware: `ContextInjectionMiddleware` (passthrough)
- System prompt with conversation phases (INTAKE → GLOBAL GOALS → CHECK-INS)
- 28 tests passing

**Phase 1 (Real Context Management):**
- Firestore append-only versioning (`user_context/{user_id}/versions/{timestamp}`)
- Real `update_user_context` tool (regex parsing)
- Real `ContextInjectionMiddleware` (loads from Firestore, injects to messages)
- **Production URL:** `https://conversational-agent-meqmyk4w5q-uc.a.run.app`
- **Verified:** Context persistence, agent recall, versioning working

**Phase 2 (Tool Events):**
- `/tool_event` endpoint (JSON response)
- `ToolEventBody` schema validation
- `NotificationGatingMiddleware` (stub for Phase 4)
- System prompt includes SYSTEM EVENTS section
- Streaming echo fix (filter AI messages only)
- **Deployed & Verified:** Both endpoints working in production

**Phase 3 (iOS Integration) - In Progress:**
- ✅ Phase 3.1: Foundation (complete)
  - `ApiClient.sendToolEvent()` method
  - `ToolEventService` for event handling
  - Debug test verified with production backend
- 🔄 Phase 3.2: Card system (next)
  - Remove debug UI
  - Add card rendering
  - Agent-driven getting_started flow

### 🔜 Remaining

**Phase 4 (Agent Replaces Intervention Selector):**
- Background job: state_estimate → tool_event
- Agent evaluates health metrics
- Real `send_notification` tool implementation
- Deprecate intervention_selector

---

## Production Endpoints

**Service:** `https://conversational-agent-meqmyk4w5q-uc.a.run.app`

**Endpoints:**
- `GET /health` - Health check
- `POST /chat` - User text messages (streaming SSE)
- `POST /tool_event` - System events (JSON response)

**Auth:** Bearer token (Identity Platform or `mock.<user_id>`)

**GCP Resources:**
- Project: `shift-dev-478422`
- Firestore: `user_context/{user_id}/versions/{timestamp_id}`
- BigQuery: `shift_data.app_interactions`, `shift_data.state_estimates`
- Cloud Run: `conversational-agent` (us-central1)

---

## Overview

Migration from hardcoded intervention system to agent-based architecture using LangChain 1.0.

**Core Principle:** Agent is the orchestration layer for all user interactions and decision-making.

### Current System
```
Watch → Backend → Intervention Selector (hardcoded rules) → iOS
iOS actions → Hardcoded flows → Limited context
```

### New System
```
Watch → Data Pipeline → State Estimates (stored)
                              ↓
User/System Events → Agent (context-aware decisions) → iOS
                       ↑
              Middleware (gating, context injection)
```

**Key Principle:**
- **Data Pipelines** handle ELT (Extract, Load, Transform)
- **Agent** handles decisions (what to do, when to notify, how to respond)

---

## Phase 1: Agent Core (Foundation) ✅ COMPLETED

**Status:** Deployed 2025-12-31

**Goal:** Working agent with tools, testable locally

### What to Build

#### 1. System Prompt

```python
COACH_SYSTEM_PROMPT = """
You are a GROW-based health coach for SHIFT.

USER JOURNEY PHASES:
1. Intake: Gather profile information
   - Name, age, experience level
   - Notification preferences
   - Current fitness baseline
   
2. Global Goals: Define long-term objectives
   - Healthspan targets (body fat %, FFMI, balance)
   - Timeline and motivation
   - Key milestones
   
3. Check-ins: Ongoing guidance
   - Daily/weekly GROW conversations
   - Workout preparation and advice
   - Progress tracking and adjustments

YOUR RESPONSIBILITIES:
- Detect which phase the user is in
- Gather missing information before advancing phases
- Recognize when user mentions updates to prior phases
- Update UserGoalsAndContext via the update_user_context tool
- Use GROW framework (Goal, Reality, Options, Way forward) for check-ins
- Be encouraging, concise, and action-oriented

CONTEXT AWARENESS:
You have access to:
- User profile and preferences (injected via middleware)
- Global goals and current focus
- Recent health metrics (HRV, sleep, activity)
- Conversation history

Use this context to personalize responses and detect changes.

NOTIFICATION DECISIONS:
When health metrics change significantly:
- Consider user's notification preferences
- Evaluate significance relative to their goals
- Only use send_notification tool if truly helpful
- Default to passive (wait for user to engage)

TOOL USAGE:
- update_user_context: When user provides new information (profile, goals, focus)
- send_notification: Only when proactive outreach is warranted and allowed
"""
```

#### 2. Tools

**update_user_context Tool:**
```python
from pydantic import BaseModel
from typing import Optional, List, Dict
from datetime import datetime

class Profile(BaseModel):
    name: Optional[str]
    age: Optional[int]
    experience_level: Optional[str]  # "beginner", "intermediate", "advanced"
    notification_preference: str = "balanced"  # "off", "minimal", "balanced", "proactive"
    quiet_hours: Optional[Dict[str, str]]  # {"start": "22:00", "end": "08:00"}

class Goals(BaseModel):
    healthspan_objectives: List[str]  # ["reach 12% body fat", "FFMI 23", "improve balance"]
    timeline: Optional[str]  # "6 months", "1 year"
    current_cycle: Optional[str]  # "cutting March-May", "maintenance"
    active_focus: Optional[str]  # "preparing for surf session tomorrow"

class Context(BaseModel):
    last_checkin: Optional[datetime]
    last_grow_goal: Optional[str]  # Most recent G from GROW
    current_W: Optional[str]  # "What will you do next" from last GROW

class UserGoalsAndContext(BaseModel):
    """Complete user context - agent maintains this structure"""
    profile: Profile
    goals: Goals
    context: Context

@tool
def update_user_context(updates: UserGoalsAndContext) -> str:
    """
    Update any part of user context. Agent decides what changed.
    
    Examples:
    - User: "I'm Sarah, 32 years old" → updates profile.name, profile.age
    - User: "I want to get to 12% body fat" → updates goals.healthspan_objectives
    - User: "Let's focus on tomorrow's workout" → updates goals.active_focus
    """
    # Merge updates into Firestore
    store_user_context(updates)
    return "Context updated successfully"
```

**send_notification Tool:**
```python
@tool
def send_notification(
    message: str,
    priority: str = "normal"  # "low", "normal", "high"
) -> str:
    """
    Send push notification to user's device.
    
    Only use when:
    - User preferences allow notifications
    - Event is significant relative to their goals
    - Message provides clear, actionable value
    
    Examples:
    - HRV dropped + user has stress management goal → send breathing exercise suggestion
    - Approaching workout time + user asked for reminders → send prep notification
    """
    # Send via iOS push notification service
    return "Notification sent"
```

#### 3. ContextInjectionMiddleware

```python
from langchain.agents.middleware import AgentMiddleware

class ContextInjectionMiddleware(AgentMiddleware):
    """Load and inject layered context into agent prompt."""
    
    def before_model(self, request):
        user_id = request.runtime.user_id
        
        # Layer 1: Profile (stable, cached)
        profile = get_profile(user_id)  # From Firestore
        
        # Layer 2: Global Goals (long-term, evolves slowly)
        global_goals = get_global_goals(user_id)  # From Firestore
        
        # Layer 3: Current Focus (active plans)
        current_focus = get_current_focus(user_id)  # From Firestore
        
        # Layer 4: Recent Events (7-day window)
        recent_events = get_recent_events(user_id, days=7)  # From BigQuery
        
        # Layer 5: Conversation (token-limited)
        messages = trim_messages(request.messages, max_tokens=2000)
        
        # Inject as system context
        system_context = f"""
        PROFILE: {profile}
        GLOBAL GOALS: {global_goals}
        CURRENT FOCUS: {current_focus}
        RECENT EVENTS: {recent_events}
        """
        
        return request.override(
            system_prompt=system_context + COACH_SYSTEM_PROMPT,
            messages=messages
        )
```

**Helper Functions:**
```python
def get_profile(user_id: str) -> dict:
    """Load user profile from Firestore."""
    # Firestore: user_context/{user_id}
    pass

def get_global_goals(user_id: str) -> dict:
    """Load global goals from Firestore."""
    pass

def get_current_focus(user_id: str) -> dict:
    """Load current focus from Firestore."""
    pass

def get_recent_events(user_id: str, days: int = 7) -> list:
    """Load recent state_estimates from BigQuery."""
    # Query: state_estimates WHERE user_id AND timestamp >= NOW() - days
    pass
```

#### 4. agent.py

```python
from langchain.agents import create_agent
from langchain.agents.middleware import SummarizationMiddleware

agent = create_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[
        update_user_context,
        send_notification,
    ],
    middleware=[
        ContextInjectionMiddleware(),
        SummarizationMiddleware(
            model="claude-sonnet-4-5-20250929",
            trigger={"tokens": 2000}
        ),
    ],
    system_prompt=COACH_SYSTEM_PROMPT
)

# __main__ test
if __name__ == "__main__":
    # Smoke test: does agent creation work?
    response = agent.invoke({
        "messages": [{"role": "user", "content": "Hi, I'm new here"}]
    })
    print(response)
```

#### 5. agent_service.py

```python
from typing import Dict, Any

class AgentService:
    """User isolation and thread management."""
    
    def __init__(self, agent):
        self.agent = agent
    
    def get_thread_id(self, user_id: str, thread_id: Optional[str] = None) -> str:
        """Generate user-isolated thread ID."""
        if thread_id:
            return f"user_{user_id}_thread_{thread_id}"
        return f"user_{user_id}_active"
    
    def invoke(self, user_id: str, message: str, thread_id: Optional[str] = None) -> Dict[str, Any]:
        """Invoke agent with user isolation."""
        full_thread_id = self.get_thread_id(user_id, thread_id)
        
        result = self.agent.invoke(
            {"messages": [{"role": "user", "content": message}]},
            config={
                "configurable": {"thread_id": full_thread_id},
                "runtime": {"user_id": user_id}
            }
        )
        
        return result
```

#### 6. main.py

```python
from fastapi import FastAPI, Depends
from agent import create_agent
from agent_service import AgentService
from auth import get_current_user

app = FastAPI()

# Initialize agent
agent = create_agent()

@app.post("/chat")
async def chat_endpoint(
    message: str,
    user_id: str = Depends(get_current_user)
):
    service = AgentService(agent)
    result = service.invoke(user_id=user_id, message=message)
    return {"response": result["messages"][-1].content}

@app.get("/health")
async def health():
    return {"status": "ok"}
```

### Testing Progression

1. **`__main__` test**:
   ```bash
   cd pipeline/conversational_agent
   python -m agent
   ```
   - Expected: Agent responds to "Hi, I'm new here"
   - Verify: No crashes, middleware loads, tools registered

2. **Unit test**:
   ```python
   def test_agent_has_tools():
       assert len(agent.tools) == 2
   
   def test_context_injection():
       # Mock user_id, verify context loaded
       pass
   ```

3. **Local test**:
   ```bash
   uvicorn main:app --reload
   
   # In another terminal
   curl -X POST http://localhost:8000/chat \
     -H "Authorization: Bearer mock.testuser" \
     -d "message=Hi, I'm Sarah"
   ```
   - Expected: Agent asks follow-up questions
   - Verify: Server logs show middleware, tools called

4. **Integration test**:
   - Deploy to Cloud Run
   - Test with real Firestore and BigQuery
   - Verify: Context persists across messages

5. **E2E test**:
   - Fresh user: "Hi, I'm Sarah, 32 years old"
   - Check: Firestore has profile.name="Sarah", profile.age=32
   - Second message: "What's my name?"
   - Expected: Agent responds "Sarah"

**Done When:** Agent responds to chat, updates Firestore, recalls context

---

## Phase 2: Tool Events ✅ COMPLETED

**Status:** Deployed 2025-12-31

**Goal:** iOS can send structured events to agent

### What to Build

#### 1. Tool Event Schema

**File:** `pipeline/conversational_agent/schemas.py`

```python
from pydantic import BaseModel
from typing import Optional, Any

class ToolEventBody(BaseModel):
    """Schema for /tool_event endpoint"""
    type: str  # "app_opened", "card_tapped", "rating_submitted", etc.
    intervention_key: Optional[str] = None
    suggested_action: Optional[str] = None
    context: Optional[str] = None
    value: Optional[Any] = None
    timestamp: str
    thread_id: Optional[str] = None
```

#### 2. /tool_event Endpoint

**File:** `pipeline/conversational_agent/main.py`

```python
from langchain.messages import ToolMessage
import json
from uuid import uuid4

@app.post("/tool_event")
async def tool_event_endpoint(
    body: ToolEventBody,
    user_id: str = Depends(get_current_user)
):
    # Convert to ToolMessage
    tool_message = ToolMessage(
        content=json.dumps(body.dict()),
        tool_call_id=str(uuid4())
    )
    
    service = AgentService(agent)
    result = service.invoke(
        user_id=user_id,
        messages=[tool_message],
        thread_id=body.thread_id
    )
    
    return {
        "status": "ok",
        "event_type": body.type,
        "response": result["messages"][-1].content
    }
```

#### 3. NotificationGatingMiddleware

**File:** `pipeline/conversational_agent/middleware.py`

```python
class NotificationGatingMiddleware(AgentMiddleware):
    """Deterministic filtering before agent invocation."""
    
    def before_agent(self, state):
        """Return None to short-circuit, or state to continue."""
        
        # Only gate health_metric_changed events
        if state.trigger != "health_metric_changed":
            return state
        
        user_id = state.runtime.user_id
        user_prefs = get_user_context(user_id)
        
        # Gate 1: Notification preference
        if user_prefs.profile.notification_preference == "off":
            return None  # Short-circuit
        
        # Gate 2: Quiet hours
        if is_quiet_hours(user_prefs.profile.quiet_hours):
            return None
        
        # Gate 3: Recently notified
        if recently_notified(user_id, within_hours=4):
            return None
        
        # All gates passed → let agent decide
        return state
```

**Helper Functions:**
```python
def is_quiet_hours(quiet_hours: dict) -> bool:
    """Check if current time is in user's quiet hours."""
    if not quiet_hours:
        return False
    
    from datetime import datetime
    now = datetime.now().time()
    start = datetime.strptime(quiet_hours["start"], "%H:%M").time()
    end = datetime.strptime(quiet_hours["end"], "%H:%M").time()
    
    if start <= end:
        return start <= now <= end
    else:  # Crosses midnight
        return now >= start or now <= end

def recently_notified(user_id: str, within_hours: int) -> bool:
    """Check if notification sent recently (Phase 2: stub)."""
    # TODO Phase 4: Query BigQuery for recent send_notification events
    return False
```

#### 4. Update Agent Creation

**File:** `pipeline/conversational_agent/agent.py`

```python
agent = create_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[update_user_context, send_notification],
    middleware=[
        NotificationGatingMiddleware(),  # NEW - runs first
        ContextInjectionMiddleware(),
    ],
    system_prompt=COACH_SYSTEM_PROMPT
)
```

#### 5. Update System Prompt

Add to `COACH_SYSTEM_PROMPT`:

```python
SYSTEM EVENTS:
You may receive events from the iOS app formatted as ToolMessages.

Event types:
- app_opened: User opened the app (respond with greeting)
- app_opened_first_time: User's first app launch (start intake)
- card_tapped: User tapped an intervention card (engage with suggested_action)
- rating_submitted: User provided a rating (acknowledge and adjust)
- flow_completed: User completed a multi-step flow (congratulate, next steps)
- health_metric_changed: Significant health metric change (evaluate, maybe notify)

Respond naturally to these events as part of the conversation.
```

### Testing Progression

1. **`__main__` test**:
   ```python
   # Add to agent.py
   if __name__ == "__main__":
       # Test tool event
       from langchain.messages import ToolMessage
       
       tool_event = ToolMessage(
           content=json.dumps({"type": "app_opened", "timestamp": "..."}),
           tool_call_id="test-001"
       )
       
       result = agent.invoke({"messages": [tool_event]})
       print(result)
   ```

2. **Unit test**:
   ```python
   def test_tool_event_schema():
       event = ToolEventBody(type="app_opened", timestamp="2025-12-31T10:00:00Z")
       assert event.type == "app_opened"
   
   def test_notification_gating():
       # Mock user with prefs="off"
       # Verify middleware returns None
       pass
   ```

3. **Local test**:
   ```bash
   curl -X POST http://localhost:8000/tool_event \
     -H "Authorization: Bearer mock.testuser" \
     -H "Content-Type: application/json" \
     -d '{
       "type": "app_opened",
       "timestamp": "2025-12-31T10:00:00Z"
     }'
   ```

4. **Integration test**:
   - Deploy to GCP
   - Send tool_event from curl
   - Verify: Agent responds appropriately
   - Check: BigQuery logs event

5. **E2E test**:
   - Fresh user opens app
   - iOS sends app_opened_first_time
   - Agent starts intake conversation
   - User taps stress card
   - iOS sends card_tapped with intervention_key
   - Agent asks for stress rating

**Done When:** Tool events flow to agent, middleware gates work, responses natural

---

## Phase 3: iOS Integration 🔄 IN PROGRESS

**Status:** Phase 3.1 complete, Phase 3.2 next

**Goal:** iOS sends tool_events for user actions, displays agent responses

### Phase 3.1: Foundation ✅ COMPLETE

#### 1. Add sendToolEvent to API Client

**File:** `ios_app/ios_app/ApiClient.swift`

```swift
func sendToolEvent(event: [String: Any]) async throws -> [String: Any] {
    let jsonData = try JSONSerialization.data(withJSONObject: event)
    let responseData = try await post(path: "/tool_event", bodyData: jsonData)
    
    guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
        throw ApiError.httpError(statusCode: 0, message: "Invalid JSON")
    }
    
    return json
}
```

### Phase 3.2: Card System 🔄 NEXT

#### 2. Update Card Tap Handler

**File:** `ios_app/ios_app/InterventionDetailView.swift`

**Before:**
```swift
Button {
    // PROBLEM: This doesn't work - just injects text into chat
    if let prompt = intervention.action?.prompt {
        chatViewModel.injectMessage(role: "assistant", text: prompt)
    }
    dismiss()
} label: {
    Text("Try it")
}
```

**After:**
```swift
Button {
    handleTryIt()
} label: {
    Text("Try it")
}

private func handleTryIt() {
    Task {
        let event: [String: Any] = [
            "type": "card_tapped",
            "intervention_key": intervention.interventionKey,
            "suggested_action": "rate_stress_1_to_5",  // Could come from intervention
            "context": "User tapped \(intervention.title) card",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        do {
            let response = try await apiClient.sendToolEvent(event: event)
            // Agent decides what to do, might ask for rating or provide guidance
        } catch {
            print("Failed to send tool_event: \(error)")
        }
    }
    
    dismiss()
}
```

#### 3. App Launch Handler

**File:** `ios_app/ios_app/ios_appApp.swift` or `AppShellView.swift`

```swift
.onAppear {
    // Detect first launch vs subsequent
    let isFirstLaunch = UserDefaults.standard.bool(forKey: "has_launched_before") == false
    
    let eventType = isFirstLaunch ? "app_opened_first_time" : "app_opened"
    
    Task {
        let event: [String: Any] = [
            "type": eventType,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        try? await apiClient.sendToolEvent(event: event)
    }
    
    if isFirstLaunch {
        UserDefaults.standard.set(true, forKey: "has_launched_before")
    }
}
```

#### 4. Getting Started Flow Completion

**File:** `ios_app/ios_app/OnboardingExperienceView.swift` (or wherever getting_started lives)

```swift
Button("Start") {
    Task {
        // Record flow completion
        let event: [String: Any] = [
            "type": "flow_completed",
            "flow_id": "getting_started",
            "flow_version": "v1",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        try? await apiClient.sendToolEvent(event: event)
    }
    
    dismiss()
}
```

### Testing Progression

1. **Build test**:
   ```bash
   cd ios_app
   xcodebuild -scheme ios_app -project ios_app.xcodeproj build
   ```
   - Verify: No compilation errors

2. **Local test**:
   - Point iOS at local server (update baseURL to `http://localhost:8000`)
   - Tap stress card
   - Verify: `/tool_event` POST appears in server logs
   - Verify: Agent responds appropriately

3. **Integration test**:
   - Point iOS at GCP (update baseURL to cloud run URL)
   - Tap stress card
   - Verify: Agent responds
   - Verify: Chat shows agent's message

4. **E2E test**:
   - Fresh user opens app
   - Check: `app_opened_first_time` event in BigQuery
   - Check: Agent asks for name in chat
   - User provides name
   - Check: Firestore has updated profile
   - Tap stress card
   - Check: `card_tapped` event in BigQuery
   - Check: Agent asks for stress rating
   - User provides rating
   - Check: `rating_submitted` event in BigQuery
   - Check: Agent responds appropriately

**Done When:** iOS actions flow through agent, conversations feel natural

---

## Phase 4: Agent Replaces Intervention Selector 🔜

**Goal:** Agent decides interventions, not hardcoded rules

### What to Build

#### 1. Background Job - State Estimate → Tool Event

**New Cloud Function or scheduled job:**

```python
def on_state_estimate_created(event, context):
    """Triggered when new state_estimate is written to BigQuery."""
    
    # Parse state_estimate
    state = parse_state_estimate(event)
    
    # Check if significant change
    if is_significant_change(state):
        # Send tool_event to agent
        tool_event = {
            "type": "health_metric_changed",
            "metric": "hrv",
            "change": state.hrv_change,
            "threshold_crossed": "low",
            "timestamp": state.timestamp
        }
        
        # POST to /tool_event
        send_tool_event(state.user_id, tool_event)

def is_significant_change(state) -> bool:
    """Determine if state change warrants agent evaluation."""
    # HRV dropped >15%
    # Stress score >0.7
    # Sleep quality dropped significantly
    pass
```

#### 2. Agent Evaluates and Decides

Agent receives tool_event via NotificationGatingMiddleware:
- Middleware checks: prefs, quiet hours, rate limits
- If gates pass: agent invokes with health_metric_changed event
- Agent sees full context: profile, goals, recent events
- Agent decides: call `send_notification` or NOOP

#### 3. Deprecate intervention_selector

**Steps:**
1. Keep intervention_selector running initially
2. Log when agent decision differs from selector decision
3. Monitor for N days
4. If agent quality >= selector: disable selector
5. Remove selector code

### Testing Progression

1. **Unit test**:
   ```python
   def test_health_metric_triggers_notification():
       # Mock: HRV dropped, user has stress goal, prefs allow notifications
       event = {"type": "health_metric_changed", "metric": "hrv", "change": -15}
       response = agent.invoke({"messages": [ToolMessage(content=json.dumps(event))]})
       # Verify: send_notification tool called
   
   def test_health_metric_respects_prefs():
       # Mock: HRV dropped, user prefs = "off"
       # Verify: middleware short-circuits, no agent invoke
   ```

2. **Local test**:
   - Manually insert state_estimate in BigQuery
   - Trigger background job
   - Verify: `/tool_event` called
   - Verify: Agent decides appropriately (notification sent or not)

3. **Integration test**:
   - Deploy background job
   - Insert real state_estimate
   - Verify: Agent receives event
   - Verify: Notification sent (if appropriate)
   - Check: BigQuery logs for decision reasoning

4. **E2E test**:
   - Real HRV data from watch
   - Pipeline: watch_events → state_estimator → state_estimate created
   - Background job: state_estimate → tool_event
   - Agent: evaluates context → sends notification (or not)
   - iOS: receives notification
   - BigQuery: complete event chain logged
   - Firestore: context updated if user interacts

**Done When:** Agent controls all intervention decisions, intervention_selector deprecated

---

## Testing Philosophy

**Build smallest testable units, test at each layer:**

1. **`__main__`**: Smoke test - does it run without crashing? Happy path only.
2. **Unit test**: Happy path + simple variations. For bugs: TDD (write failing test, fix, pass).
3. **Local test**: Run service locally, `curl` or use client to verify behavior.
4. **Integration test**: Deploy to GCP, `curl` endpoints, verify cloud services work.
5. **E2E test**: Full user flow, check tables/logs before and after, verify complete chain.

**Test coverage emerges from TDD bug fixes.** Don't pre-fill extensive test suites. When bugs happen:
- Write test that reproduces bug (fails)
- Fix bug
- Test passes
- Coverage grows organically

---

## Data Storage Reference

### Firestore (Agent State, Real-time)
**Collections:**
- `user_context/{user_id}/versions/{timestamp_id}` - Append-only versioned context
  - Each save creates new doc: `YYYYMMDD_HHMMSS_microseconds`
  - `get_user_context()` queries latest: `ORDER BY created_at DESC LIMIT 1`
- `agent_conversations/{user_id}/messages` - LangChain checkpointing

**Access:** Read/write on every agent interaction

### BigQuery (Analytics, Historical)
**Tables:**
- `state_estimates` - Pipeline output (read by agent for context)
- `app_interactions` - Event log (tool_events, chat, notifications)
- `intervention_instances` - DEPRECATED after migration

**Access:** Batch reads for context, async writes for logging

### Data Pipelines (Unchanged)
- `watch_events` → ingest to BigQuery
- `state_estimator` → calculate metrics, write to BigQuery

---

## References

- [LangChain 1.0 Release](https://blog.langchain.com/langchain-langchain-1-0-alpha-releases/)
- [LangChain Agents](https://python.langchain.com/docs/how_to/#agents)
- [LangChain Middleware](https://python.langchain.com/docs/how_to/middleware/)
- [Production Service](https://console.cloud.google.com/run/detail/us-central1/conversational-agent/metrics?project=shift-dev-478422)
- [Firestore Console](https://console.cloud.google.com/firestore/databases/-default-/data/panel/user_context?project=shift-dev-478422)

---

**Authors:** Sylvester (CTO), Claude (AI Architecture Consultant)