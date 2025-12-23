"""FastAPI entrypoint. Handles HTTP and auth only."""

import os
from fastapi import FastAPI, Depends
from fastapi.responses import StreamingResponse

from agent import create_grow_agent
from agent_service import AgentService, ChatRequest
from auth import get_current_user
from schemas import ChatRequestBody

GCP_PROJECT_ID = os.environ["GCP_PROJECT_ID"]

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY")
if not ANTHROPIC_API_KEY:
    from google.cloud import secretmanager
    ANTHROPIC_API_KEY_SECRET_ID = os.environ.get("ANTHROPIC_API_KEY_SECRET_ID", "anthropic-api-key")
    client = secretmanager.SecretManagerServiceClient()
    secret_name = f"projects/{GCP_PROJECT_ID}/secrets/{ANTHROPIC_API_KEY_SECRET_ID}/versions/latest"
    response = client.access_secret_version(request={"name": secret_name})
    ANTHROPIC_API_KEY = response.payload.data.decode("UTF-8")

agent = create_grow_agent(project_id=GCP_PROJECT_ID)

app = FastAPI()


@app.post("/chat")
async def chat(
    body: ChatRequestBody,
    user_id: str = Depends(get_current_user)
):
    """Streaming conversational endpoint."""
    service = AgentService(user_id=user_id, agent=agent)
    
    async def generate():
        async for chunk in service.chat_stream(ChatRequest(
            user_id=user_id,
            message=body.message,
            thread_id=body.thread_id
        )):
            yield chunk
    
    return StreamingResponse(
        generate(),
        media_type="text/event-stream"
    )


@app.get("/health")
async def health():
    return {"status": "ok"}

