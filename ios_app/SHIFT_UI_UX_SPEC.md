# SHIFT Chat UI & UX Contract (MVP)

This document defines the **non-negotiable UI/UX structure** for the SHIFT iOS app MVP.
It exists to prevent UI sprawl, preserve a calm agentic experience, and enable fast iteration
without re-litigating design decisions.

This is a **behavioral contract**, not a visual design spec.

---

## Core Principle

**Chat is the product.**

Everything else (cards, side panels, settings) exists only to support the conversational agent.
Chat must always remain accessible and primary.

---

## Navigation Structure

### Root View Hierarchy

```

NavigationStack
└── ZStack
    ├── ChatView (primary, always visible)
    ├── SidePanelOverlay (offscreen / overlay)
    ├── CardOverlay (optional, ephemeral)

```

### ChatView
- Default and primary surface
- Always accessible
- Never replaced by tabs, dashboards, or modal flows
- All meaningful interaction happens here

---

## Side Panel (Utility Overlay)

### Purpose
The side panel is **utility-only**.  
It contains no coaching logic, insights, or metrics.

### Behavior
- Overlay (slides in over chat)
- Dismissible via swipe or tap outside
- No deep navigation stacks
- No stateful logic beyond visibility

### MVP Contents
- New Chat
- Past Chats (list)
- User Menu
  - Settings
  - Login / Logout

### Explicitly Out of Scope (MVP)
- Insights
- Metrics
- Cards
- Coaching flows
- Dashboards

---

## Cards (Interventions & Check-ins)

### Definition
A **card is an affordance**, not content.

Its sole purpose is to answer:
> “Is *now* a good moment to engage?”

Cards never collect input and never replace chat.

---

## Card Visibility Rules (MVP)

- 0 or 1 card visible at a time
- Cards are **time-bound**
- Cards disappear when:
  - Accepted (user taps)
  - Dismissed (user closes)
  - Expired (TTL elapsed)
- No card history or feed
- No persistent cards

> Scrolling collections of cards are considered a design smell and are explicitly out of scope for MVP.

---

## Card Types (MVP)

### 1. In-the-moment Intervention
- Triggered by detected state (e.g. acute stress)
- Visible only during the relevant time window
- Short, calm copy
- CTA opens chat

### 2. Periodic Check-in
- Triggered by schedule or uncertainty in state
- Example: daily lightweight or weekly reflection
- CTA opens chat
- Check-in questions are asked *in chat*, not on the card

### 3. Post-event Follow-up
- Triggered after detected event + cooldown
- Short TTL
- CTA opens chat for reflection

---

## Card → Chat Contract (Critical)

Cards do not "fake" user input or collect data directly. They trigger agent conversations via structured events.

### On Card Tap
- The app sends a `/tool_event` request to the agent service with structured event data.

**Event Schema:**
```json
{
  "type": "card_tapped",
  "intervention_key": "stress_checkin",
  "suggested_action": "rate_stress_1_to_5",
  "context": "User tapped stress check-in card",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

**iOS Implementation:**
```swift
apiClient.post("/tool_event", body: [
    "type": "card_tapped",
    "intervention_key": card.interventionKey,
    "suggested_action": card.suggestedAction,
    "context": "User tapped \(card.title) card"
])
```

### Agent Response
- Agent receives event via middleware (context injection, gating)
- Agent processes event and responds with appropriate message or action
- Response streams to iOS via `/chat` endpoint (SSE)
- iOS displays agent response in chat interface

**Response Example:**
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

### Agent Responsibility
- The agent system prompt must:
  - Detect card events via `/tool_event` endpoint
  - Initiate the appropriate conversational flow based on event type and context
  - Ask questions and guide interaction in chat
  - Use `update_user_context` tool when user provides information

**Key Principle:** Chat owns the flow. Cards only initiate it via structured events.

---

## Card Lifecycle & Instrumentation

Cards may be logged using the existing intervention/check-in table.

### Minimum Required Events
- `card_shown`
- `card_accepted`

### Optional (Nice-to-have)
- `card_dismissed`
- `card_expired`

These events are for analysis, not UI resurrection.

---

## First-Run / Orientation Flow

### Orientation Cards
- Presented only on first launch
- Displayed as a temporary card walkthrough
- Explain:
  - What SHIFT is
  - Mind / Body / Bell
  - What to expect from the agent
- Chat remains visible behind cards

### Completion Rules
- Orientation completion is persisted
- Once complete:
  - Orientation cards never reappear
  - App always opens directly to chat

---

## App Launch Priority

When the app opens:

1. If there is an active, relevant card → show card
2. Otherwise → show chat only
3. Side panel is always closed by default

No stacking. No ambiguity.

---

## Explicitly Out of Scope (MVP)

The following are intentionally deferred:
- Card feeds or scrolling trays
- Multiple simultaneous cards
- User-configurable card preferences
- Dashboards or metric-first views
- Browsing past interventions

---

## Design Intent

SHIFT should feel:
- Calm
- Optional
- Present but not demanding

Over-intervention erodes trust faster than under-intervention.
Default behavior should be **silence unless relevance is high**.

---

## Summary

- Chat is sacred
- Cards are ephemeral
- Side panel is utilities only
- Less is more

This contract exists so we can build quickly without reintroducing complexity.