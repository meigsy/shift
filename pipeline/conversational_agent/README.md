# SHIFT Conversational Agent Pipeline

GROW coaching model conversational agent using LangChain 1.0 with Firestore persistence and streaming SSE responses.

## Architecture

Three-layer separation:
1. **agent.py** - LangChain agent creation, no business logic, testable via `__main__`
2. **agent_service.py** - User isolation, thread management, coordinates agent, testable via `__main__`
3. **main.py** - FastAPI entrypoint, HTTP/auth, delegates to service layer

### Middleware Stack

The agent uses a middleware stack for progressive context disclosure and deterministic gating:

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
- Loads from Firestore (user context) and BigQuery (state estimates, interactions)
- Injects as system context before agent invocation

## Required Environment Variables

Set these before running:

```bash
export GCP_PROJECT_ID="shift-dev-478422"
export ANTHROPIC_API_KEY="sk-ant-..."
```

Missing variables will cause immediate startup failure (by design - fail fast, fail loud).

Note: In production (Cloud Run), Terraform injects `ANTHROPIC_API_KEY` from Secret Manager as an environment variable. The service code is transparent to this - it only reads from environment variables.

## Usage Examples

### Test Agent Directly

```bash
python -m pipeline.conversational_agent.agent
```

### Test Service Layer

```bash
python -m pipeline.conversational_agent.agent_service
```

### Run Locally

```bash
uv run uvicorn pipeline.conversational_agent.main:app --reload
```

### Test Endpoints

```bash
# Health check
curl http://localhost:8000/health

# Chat (with mock auth)
curl -N -H "Authorization: Bearer mock.test" \
  -H "Content-Type: application/json" \
  -d '{"message":"I want to sleep better"}' \
  http://localhost:8000/chat

# Tool event (with mock auth)
curl -H "Authorization: Bearer mock.test" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "card_tapped",
    "intervention_key": "stress_checkin",
    "suggested_action": "rate_stress_1_to_5",
    "context": "User tapped stress check-in card",
    "timestamp": "2025-01-15T10:30:00Z"
  }' \
  http://localhost:8000/tool_event
```

## Testing

Run all tests:

```bash
uv run pytest pipeline/conversational_agent/tests/
```

Run specific test file:

```bash
uv run pytest pipeline/conversational_agent/tests/test_agent.py
```

## Deployment

### Build Container

```bash
cd pipeline/conversational_agent
gcloud builds submit --tag gcr.io/shift-dev-478422/conversational-agent:latest .
```

### Deploy via Terraform

```bash
cd terraform/projects/dev
terraform apply -var="conversational_agent_image=gcr.io/shift-dev-478422/conversational-agent:latest"
```

### Deploy via Root Script

```bash
./deploy.sh --build
```

## User Isolation

Thread IDs are automatically prefixed with user_id:
- Default thread: `user_{user_id}_active`
- Custom thread: `user_{user_id}_thread_{thread_id}`

This ensures complete user isolation in Firestore.

## Tools

### update_user_context

Agent maintains complete user state via structured updates.

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
```

**Usage:**
- Agent calls this tool when user provides new information (profile, goals, focus)
- Updates stored in Firestore for fast access on subsequent invocations

### send_notification

Agent proactively sends push notification to user.

**Parameters:**
- `message: str` - Notification text
- `priority: str = "normal"` - "low", "normal", "high"

**Usage:**
- Only used when: user preferences allow, event is significant, message provides clear value
- Gated by NotificationGatingMiddleware to prevent spam

## Conversation Phases

The agent navigates users through three phases:

1. **[Intake]** - Gather profile information
   - Name, age, experience level
   - Notification preferences
   - Current fitness baseline
   
2. **[Global Goals]** - Define long-term objectives
   - Healthspan targets (body fat %, FFMI, balance)
   - Timeline and motivation
   - Key milestones
   
3. **[Check-ins]** - Ongoing guidance
   - Daily/weekly GROW conversations
   - Workout preparation and advice
   - Progress tracking and adjustments

Agent detects which phase the user is in and gathers missing information before advancing.

## Endpoints

### `/chat` (User Messages)

**Endpoint**: `POST /chat` (SSE streaming)

**Purpose**: Receives user text messages and returns agent responses via Server-Sent Events.

**Request Schema:**
```json
{
  "message": "I want to sleep better",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

**Response**: Streams agent response as SSE chunks.

### `/tool_event` (Structured Events)

**Endpoint**: `POST /tool_event`

**Purpose**: Receives structured events from iOS and background systems. Agent processes these to make context-aware decisions.

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

## Streaming

Responses are streamed as Server-Sent Events (SSE). FastAPI automatically formats chunks when `media_type="text/event-stream"` is set - do NOT manually add "data:" prefix.


