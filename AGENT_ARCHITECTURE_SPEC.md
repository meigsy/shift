# SHIFT Agent Architecture Specification

## Overview

This document specifies the migration from a hardcoded intervention system to an agent-based architecture using LangChain 1.0. The core principle: **the agent is the orchestration layer for all user interactions and decision-making**.

## Architecture Philosophy

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

## System Components

### 1. Endpoints

#### `/tool_event` (NEW)
Receives structured events from iOS and background systems.

**Event Types:**
- `app_opened_first_time` - User's first app launch
- `app_opened` - Subsequent app launches
- `card_tapped` - User engaged with an intervention card
- `rating_submitted` - User provided structured input (1-5 rating)
- `health_metric_changed` - Background pipeline detected significant change
- `flow_completed` - User completed a multi-step flow (e.g., getting_started)

**Request Schema:**
```json
{
  "type": "card_tapped",
  "intervention_key": "stress_checkin",
  "suggested_action": "rate_stress_1_to_5",
  "context": "User tapped stress check-in card",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

**Response:**
```json
{
  "message": "Quick check-in: How stressed do you feel (0-10)?",
  "ui_hint": "rating_scale",
  "metadata": {
    "conversation_id": "uuid",
    "requires_response": true
  }
}
```

#### `/chat` (EXISTING, Enhanced)
Receives user text messages.

**Request Schema:**
```json
{
  "message": "I'm feeling really stressed today",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

**Response:**
```json
{
  "message": "I hear you. What's going on that's making you feel stressed?",
  "metadata": {
    "conversation_id": "uuid"
  }
}
```

#### `/context` (DEPRECATED)
Will be removed after migration. Agent provides context dynamically.

### 2. Agent Service

Built on **LangChain 1.0** `create_agent` with middleware stack.

**Core Agent:**
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
        NotificationGatingMiddleware(),
        ContextInjectionMiddleware(),
        SummarizationMiddleware(
            model="claude-sonnet-4-5-20250929",
            trigger={"tokens": 2000}
        ),
    ],
    system_prompt=COACH_SYSTEM_PROMPT
)
```

### 3. Middleware Stack

Middleware provides **progressive context disclosure** and **deterministic gating**.

#### NotificationGatingMiddleware
**Purpose:** Deterministic filtering before agent invocation.

**Gates:**
- User notification preference = "off" → short-circuit, no LLM call
- Current time in quiet hours → short-circuit
- Notification sent within last 4 hours → short-circuit (rate limit)

**Returns:** `None` to stop execution, or `state` to continue.

#### ContextInjectionMiddleware
**Purpose:** Load and inject layered context into agent prompt.

**Context Layers:**
1. **Profile** (stable, cached)
   - Name, age, experience level, notification preferences
2. **Global Goals** (long-term, evolves slowly)
   - Healthspan objectives (bf%, FFMI, balance)
   - Timeline and milestones
3. **Current Focus** (active plans)
   - Current cycle (cutting, maintenance, bulking)
   - Active workout program
   - Immediate goals (tomorrow's surf session)
4. **Recent Events** (7-day window)
   - State estimates (HRV trends, sleep quality, activity levels)
   - User interactions (ratings, check-ins)
   - Workouts logged
5. **Conversation** (token-limited)
   - Recent message history (trimmed to budget)

**Implementation:**
```python
class ContextInjectionMiddleware(AgentMiddleware):
    def before_model(self, request):
        user_id = request.runtime.user_id
        
        # Load context layers from Firestore + BigQuery
        profile = get_profile(user_id)
        global_goals = get_global_goals(user_id)
        current_focus = get_current_focus(user_id)
        recent_events = get_recent_events(user_id, days=7)
        
        # Inject as system context
        system_context = f"""
        PROFILE: {profile}
        GLOBAL GOALS: {global_goals}
        CURRENT FOCUS: {current_focus}
        RECENT EVENTS: {recent_events}
        """
        
        return request.override(system_prompt=system_context + COACH_SYSTEM_PROMPT)
```

### 4. System Prompt

**Conversation Phases:**
```
[Intake] → [Global Goals] → [Check-ins]
```

**Prompt Structure:**
```
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
```

### 5. Tools

#### update_user_context
**Purpose:** Agent maintains complete user state via structured updates.

**Schema:**
```python
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

#### send_notification
**Purpose:** Agent proactively sends push notification to user.

**Parameters:**
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

### 6. Data Storage

#### Firestore (Agent State, Real-time Access)
**Collections:**
- `user_context/{user_id}` - UserGoalsAndContext object
  - Fast reads on every agent invocation
  - Writes via `update_user_context` tool
- `agent_conversations/{user_id}/messages` - LangChain checkpointing
  - Conversation history
  - Managed by LangGraph persistence

**Access Pattern:** Read/write on every agent interaction (low latency required)

#### BigQuery (Analytics, Historical Data)
**Tables:**
- `state_estimates` - Pipeline-generated health metrics
  - Written by state_estimator (Pub/Sub triggered)
  - Read by agent for recent context (via middleware)
- `app_interactions` - Event log
  - All tool_events and chat messages
  - Used for analytics and conversation summarization
- `intervention_instances` (DEPRECATED after migration)
  - Historical record, not used by agent

**Access Pattern:** Batch reads for context injection, async writes for logging

### 7. Data Pipelines (Unchanged)

**Keep existing pipelines for data processing:**

#### watch_events Pipeline
- **Trigger:** iOS sends biometric data via `/watch_events`
- **Action:** Ingest to BigQuery raw tables
- **Output:** Raw health data stored

#### state_estimator (Cloud Function)
- **Trigger:** Pub/Sub message from watch_events
- **Action:** Calculate HRV trends, stress levels, sleep quality
- **Output:** `state_estimates` table updated

**These remain deterministic data processing. Agent only decides WHAT TO DO with the data.**

### 8. iOS Changes

#### Card Interaction Updates
**Before:**
```swift
// Hardcoded prompt injection (doesn't work)
let prompt = "Help the user with stress management..."
chatViewModel.injectMessage(role: "assistant", text: prompt)
```

**After:**
```swift
// Send tool_event, let agent respond
apiClient.post("/tool_event", body: [
    "type": "card_tapped",
    "intervention_key": "stress_checkin",
    "suggested_action": "rate_stress_1_to_5",
    "context": "User tapped stress check-in card"
])
```

#### Getting Started Flow
**Keep existing UI flow** (multi-page modal with welcome, features, etc.)

**Add at completion:**
```swift
// When user taps "Start" button on final page
apiClient.post("/tool_event", body: [
    "type": "flow_completed",
    "flow_id": "getting_started",
    "timestamp": ISO8601DateFormatter().string(from: Date())
])
```

Agent sees this event and knows: intake phase complete, user ready for global goals conversation.

#### App Lifecycle Events
```swift
// First app launch
apiClient.post("/tool_event", body: ["type": "app_opened_first_time"])

// Subsequent launches
apiClient.post("/tool_event", body: ["type": "app_opened"])
```

### 9. Migration Path

#### Phase 1: Foundation (Week 1)
- [ ] Create agent service with LangChain 1.0
- [ ] Implement `/tool_event` endpoint
- [ ] Build middleware stack (gating, context injection)
- [ ] Set up Firestore schema for UserGoalsAndContext
- [ ] Deploy agent service alongside existing system (no breaking changes)

#### Phase 2: iOS Integration (Week 2)
- [ ] Update iOS to send `/tool_event` for card taps
- [ ] Add `flow_completed` event to getting_started flow
- [ ] Test agent responses to tool_events
- [ ] Keep `/context` endpoint running (fallback)

#### Phase 3: Agent Activation (Week 3)
- [ ] Route card interactions through agent instead of hardcoded prompts
- [ ] Agent handles getting_started completion → global goals conversation
- [ ] Monitor agent performance and iterate on prompts
- [ ] Keep intervention_selector running but log when agent would differ

#### Phase 4: Full Migration (Week 4)
- [ ] Disable intervention_selector (agent fully handles decisions)
- [ ] Remove `/context` endpoint
- [ ] Clean up deprecated BigQuery tables
- [ ] Archive old intervention selection code

#### Phase 5: Optimization (Ongoing)
- [ ] Tune middleware context injection (token budget optimization)
- [ ] Add conversation summarization for long histories
- [ ] Implement A/B testing for prompt variations
- [ ] Add analytics on agent decision quality

## Testing Strategy

### Unit Tests
- Middleware short-circuiting (gating logic)
- Context injection (correct layers loaded)
- Tool call validation (schema compliance)

### Integration Tests
- `/tool_event` → agent invocation → response
- `/chat` → agent invocation → response
- State updates via `update_user_context` persist to Firestore

### End-to-End Tests
1. **First-time user flow:**
   - Send `app_opened_first_time`
   - Verify agent asks for name, age
   - Update context via tool
   - Verify Firestore updated
   
2. **Card interaction flow:**
   - Send `card_tapped` with stress_checkin
   - Verify agent asks for stress rating
   - Send `rating_submitted` with value
   - Verify agent responds appropriately
   
3. **Proactive notification flow:**
   - Insert low HRV in state_estimates
   - Trigger background job → `/tool_event` health_metric_changed
   - Verify middleware gates pass
   - Verify agent calls `send_notification` (or doesn't, based on context)

### Manual Testing
- Conversation quality (does agent navigate phases correctly?)
- Context awareness (does agent remember goals and adjust advice?)
- Notification appropriateness (spam vs helpful)

## Monitoring & Observability

### Metrics to Track
- Agent invocation rate (tool_events vs chat messages)
- Middleware short-circuit rate (how often gating prevents LLM calls)
- Tool call distribution (update_user_context vs send_notification)
- Response latency (p50, p95, p99)
- Context injection size (tokens used per layer)

### Logging
- All tool_events logged to BigQuery `app_interactions`
- Agent decisions logged (why notification sent/not sent)
- Middleware gates logged (which gate triggered short-circuit)
- LangChain traces via LangSmith (conversation debugging)

## Rollback Plan

If agent performance is poor or bugs are critical:

1. **Immediate:** Re-enable `/context` endpoint (intervention_selector resumes)
2. **iOS:** Revert to hardcoded prompt injection temporarily
3. **Agent:** Keep running in shadow mode (log decisions but don't act)
4. **Debug:** Use LangSmith traces to identify prompt/context issues
5. **Fix:** Iterate on prompts/middleware in staging
6. **Retry:** Gradual rollout with feature flags

## Success Criteria

### Phase 1-2 (Foundation)
- [ ] Agent service deployed and responding to `/tool_event`
- [ ] iOS sending tool_events successfully
- [ ] No increase in error rates

### Phase 3 (Agent Activation)
- [ ] Agent handles card interactions with <2s latency (p95)
- [ ] User conversations feel natural (manual review)
- [ ] Context updates persist correctly to Firestore

### Phase 4 (Full Migration)
- [ ] `/context` endpoint removed, no rollbacks needed
- [ ] Agent decision quality >= intervention_selector baseline
- [ ] 50%+ reduction in notification spam (user feedback)

### Phase 5 (Optimization)
- [ ] Agent cost per interaction <$0.01
- [ ] Context injection optimized (token budget 90% utilized)
- [ ] User engagement up 20% (measured via check-in frequency)

## Open Questions

1. **Summarization strategy:** How often to summarize long conversations? Daily? After N messages?
2. **Context budget:** What's the optimal token allocation per context layer?
3. **Notification timing:** Should middleware enforce minimum time between notifications, or let agent decide?
4. **A/B testing:** How to test prompt variations without fragmenting user experience?

## References

- [LangChain 1.0 Release Notes](https://blog.langchain.com/langchain-langchain-1-0-alpha-releases/)
- [LangChain Agents Documentation](https://python.langchain.com/docs/how_to/#agents)
- [LangChain Middleware Guide](https://python.langchain.com/docs/how_to/middleware/)
- [Anthropic Extended Thinking Research](https://www.anthropic.com/research)

---

**Document Version:** 1.0  
**Last Updated:** 2025-01-15  
**Authors:** Sylvester (CTO), Claude (AI Architecture Consultant)
