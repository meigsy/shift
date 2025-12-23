import os
from fastapi import FastAPI, Depends
from fastapi.responses import StreamingResponse

from agent import create_grow_agent
from agent_service import AgentService
from auth import get_current_user
from schemas import ChatRequestBody

GCP_PROJECT_ID = os.environ["GCP_PROJECT_ID"]
ANTHROPIC_MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-5-20250929")

agent = create_grow_agent(project_id=GCP_PROJECT_ID, model_name=ANTHROPIC_MODEL)

app = FastAPI()


@app.post("/chat")
async def chat_endpoint(
        body: ChatRequestBody,
        user_id: str = Depends(get_current_user)
):
    service = AgentService(user_id=user_id, agent=agent)

    return StreamingResponse(
        service.chat_stream(message=body.message, thread_id=body.thread_id),
        media_type="text/event-stream"
    )


@app.get("/health")
async def health():
    return {"status": "ok"}
