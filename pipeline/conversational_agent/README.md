# SHIFT Conversational Agent Pipeline

GROW coaching model conversational agent using LangChain 1.0 with Firestore persistence and streaming SSE responses.

## Architecture

Three-layer separation:
1. **agent.py** - LangChain agent creation, no business logic, testable via `__main__`
2. **agent_service.py** - User isolation, thread management, coordinates agent, testable via `__main__`
3. **main.py** - FastAPI entrypoint, HTTP/auth, delegates to service layer

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

## Streaming

Responses are streamed as Server-Sent Events (SSE). FastAPI automatically formats chunks when `media_type="text/event-stream"` is set - do NOT manually add "data:" prefix.


