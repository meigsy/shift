# SHIFT Agent Architecture - Implementation Guide

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

## Phase 1: Agent Core (Foundation)

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
        thread = self.get_thread_id(user_id, thread_id)
        
        response = self.agent.invoke(
            {"messages": [{"role": "user", "content": message}]},
            config={"configurable": {"thread_id": thread}}
        )
        
        return response

# __main__ test
if __name__ == "__main__":
    from agent import agent
    
    service = AgentService(agent)
    response = service.invoke("test_user_123", "Hi, I'm Sarah")
    print(response)
```

#### 6. Firestore Schema Setup

**Collections:**
- `user_context/{user_id}` - UserGoalsAndContext object
- `agent_conversations/{user_id}/messages` - LangChain checkpointing

**Initialize:**
```python
from google.cloud import firestore

def setup_firestore_schema():
    """Create initial Firestore collections if they don't exist."""
    db = firestore.Client(project="shift-dev-478422")
    
    # user_context collection
    # Structure: {profile: {}, goals: {}, context: {}}
    
    # agent_conversations collection
    # Managed by LangGraph persistence automatically
    
    pass
```

#### 7. main.py - /chat Endpoint

```python
from fastapi import FastAPI, Depends
from agent_service import AgentService
from agent import agent

app = FastAPI()
service = AgentService(agent)

@app.post("/chat")
async def chat(request: ChatRequest, current_user: User = Depends(get_current_user)):
    """User text messages to agent."""
    response = service.invoke(
        user_id=current_user.user_id,
        message=request.message
    )
    
    # Log to BigQuery app_interactions
    log_chat_interaction(current_user.user_id, request.message, response)
    
    return {"message": response["output"], "metadata": {...}}
```

### Testing Progression

1. **`__main__` test**:
   ```bash
   python -m pipeline.conversational_agent.agent
   python -m pipeline.conversational_agent.agent_service
   ```
   - Verify: Agent creates, responds to simple message
   - Verify: Service isolates threads correctly

2. **Unit test**:
   ```python
   # test_agent.py
   def test_agent_updates_context():
       response = agent.invoke({
           "messages": [{"role": "user", "content": "I'm Sarah, 32 years old"}]
       })
       # Verify: update_user_context tool called with name and age
   
   def test_agent_sends_notification():
       response = agent.invoke({
           "messages": [{"role": "user", "content": "My HRV just dropped"}]
       })
       # Verify: send_notification tool called (or not, based on context)
   ```
   Run: `pytest pipeline/conversational_agent/tests/test_agent.py -v`

3. **Local test**:
   ```bash
   cd pipeline/conversational_agent
   uvicorn main:app --reload
   
   # In another terminal:
   curl -X POST http://localhost:8000/chat \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer mock.test" \
     -d '{"message": "Hi, I am new here"}'
   ```
   - Verify: Agent responds
   - Verify: Firestore updated with user context
   - Verify: BigQuery app_interactions logged

4. **Integration test**:
   ```bash
   # Deploy
   ./deploy.sh -b
   
   # Test
   curl -X POST https://conversational-agent-<hash>-uc.a.run.app/chat \
     -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
     -H "Content-Type: application/json" \
     -d '{"message": "Hi, I am Sarah"}'
   ```
   - Verify: Same behavior as local

5. **E2E test**:
   ```sql
   -- Check Firestore updated
   -- (use Firebase console or gcloud)
   
   -- Check BigQuery logged
   SELECT * FROM `shift-dev-478422.shift_data.app_interactions`
   WHERE user_id = 'test_user_123'
   ORDER BY timestamp DESC LIMIT 5;
   ```
   - Verify: user_context has name="Sarah"
   - Verify: app_interactions has chat event

**Done When:** Agent responds to chat, updates Firestore, logs to BigQuery

---

## Phase 2: Tool Events

**Goal:** Agent receives and responds to `/tool_event`

### What to Build

#### 1. NotificationGatingMiddleware

```python
class NotificationGatingMiddleware(AgentMiddleware):
    """Deterministic filtering before agent invocation."""
    
    def before_agent(self, state):
        """Short-circuit if deterministic gates fail."""
        if state.trigger == "health_metric_changed":
            user_prefs = get_user_preferences(state.user_id)
            
            # Hard gates (deterministic)
            if user_prefs.notification_preference == "off":
                return None  # Don't invoke agent
            
            if not is_quiet_hours(user_prefs.quiet_hours):
                return None  # Outside allowed time
            
            if recently_notified(state.user_id, within_hours=4):
                return None  # Rate limit
            
            # Passed gates → let agent decide
            return state
```

**Helper Functions:**
```python
def get_user_preferences(user_id: str) -> dict:
    """Load notification preferences from Firestore."""
    pass

def is_quiet_hours(quiet_hours: dict) -> bool:
    """Check if current time is in quiet hours."""
    pass

def recently_notified(user_id: str, within_hours: int) -> bool:
    """Check if notification sent recently."""
    # Query BigQuery app_interactions for recent send_notification events
    pass
```

#### 2. /tool_event Endpoint

```python
@app.post("/tool_event")
async def tool_event(
    event: Dict[str, Any],
    current_user: User = Depends(get_current_user)
):
    """System events to agent."""
    
    # Convert to ToolMessage
    from langchain.messages import ToolMessage
    
    messages = [ToolMessage(
        content=json.dumps(event),
        tool_call_id=str(uuid4())
    )]
    
    # Load context
    context = load_user_context(current_user.user_id)
    
    # Invoke agent
    response = agent.invoke({
        "messages": messages,
        "context": context
    })
    
    # Log to BigQuery
    log_tool_event(current_user.user_id, event, response)
    
    return {"response": response}
```

#### 3. Event Types

**Schema:**
```python
class ToolEvent(BaseModel):
    type: str  # app_opened, card_tapped, rating_submitted, etc.
    intervention_key: Optional[str]
    suggested_action: Optional[str]
    context: Optional[str]
    value: Optional[Any]  # For ratings, metric values, etc.
    timestamp: str

# Examples:
{
  "type": "app_opened",
  "timestamp": "2025-01-15T10:30:00Z"
}

{
  "type": "card_tapped",
  "intervention_key": "stress_checkin",
  "suggested_action": "rate_stress_1_to_5",
  "context": "User tapped stress check-in card",
  "timestamp": "2025-01-15T10:30:00Z"
}

{
  "type": "rating_submitted",
  "intervention_key": "stress_checkin",
  "value": 4,
  "timestamp": "2025-01-15T10:30:00Z"
}
```

#### 4. Update agent.py Middleware Stack

```python
agent = create_agent(
    model="claude-sonnet-4-5-20250929",
    tools=[update_user_context, send_notification],
    middleware=[
        NotificationGatingMiddleware(),  # NEW
        ContextInjectionMiddleware(),
        SummarizationMiddleware(
            model="claude-sonnet-4-5-20250929",
            trigger={"tokens": 2000}
        ),
    ],
    system_prompt=COACH_SYSTEM_PROMPT
)
```

### Testing Progression

1. **`__main__` test**:
   ```python
   # In agent_service.py
   if __name__ == "__main__":
       service = AgentService(agent)
       
       # Test tool_event
       event = {"type": "app_opened", "timestamp": "2025-01-15T10:00:00Z"}
       response = service.invoke_tool_event("test_user_123", event)
       print(response)
   ```

2. **Unit test**:
   ```python
   def test_notification_gating_middleware():
       # Mock user with notification_preference = "off"
       # Verify: middleware returns None (short-circuit)
   
   def test_agent_responds_to_card_tap():
       event = {"type": "card_tapped", "intervention_key": "stress_checkin"}
       response = agent.invoke({"messages": [ToolMessage(content=json.dumps(event))]})
       # Verify: Agent asks for stress rating
   ```

3. **Local test**:
   ```bash
   curl -X POST http://localhost:8000/tool_event \
     -H "Authorization: Bearer mock.test" \
     -d '{"type": "app_opened"}'
   ```

4. **Integration test**:
   ```bash
   curl -X POST https://conversational-agent-<hash>.run.app/tool_event \
     -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
     -d '{"type": "card_tapped", "intervention_key": "stress_checkin"}'
   ```

5. **E2E test**:
   ```sql
   SELECT * FROM `shift-dev-478422.shift_data.app_interactions`
   WHERE user_id = 'test_user_123'
     AND event_type = 'tool_event'
   ORDER BY timestamp DESC LIMIT 5;
   ```

**Done When:** Agent responds to tool_events, middleware gates working

---

## Phase 3: iOS Integration

**Goal:** iOS sends tool_events, receives agent responses

### What to Build

#### 1. iOS API Client Updates

**File:** `ios_app/ios_app/APIClient.swift`

```swift
func sendToolEvent(event: [String: Any]) async throws -> ToolEventResponse {
    let url = baseURL.appendingPathComponent("tool_event")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    
    let jsonData = try JSONSerialization.data(withJSONObject: event)
    request.httpBody = jsonData
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw APIError.invalidResponse
    }
    
    return try JSONDecoder().decode(ToolEventResponse.self, from: data)
}
```

#### 2. Card Tap Handler

**File:** `ios_app/ios_app/InterventionDetailView.swift`

**Before:**
```swift
Button {
    // Hardcoded prompt injection (doesn't work)
    chatViewModel.injectMessage(role: "assistant", text: prompt)
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

## Phase 4: Agent Replaces Intervention Selector

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
- `user_context/{user_id}` - UserGoalsAndContext
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

---

**Document Version:** 2.0  
**Last Updated:** 2025-12-30  
**Authors:** Sylvester (CTO), Claude (AI Architecture Consultant)