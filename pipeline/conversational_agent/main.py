import os
import logging
import json
from fastapi import FastAPI, Depends
from fastapi.responses import StreamingResponse

from agent import create_grow_agent, update_user_context
from agent_service import AgentService
from auth import get_current_user
from schemas import ChatRequestBody, ToolEventBody
from middleware import set_middleware_user_id

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

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


@app.post("/tool_event")
async def tool_event_endpoint(
    body: ToolEventBody,
    user_id: str = Depends(get_current_user)
):
    """
    Handle tool events from iOS (card taps, app opens, ratings, etc.)
    Converts event to a system event message and invokes agent.
    """
    logger.info(f"[tool_event] Received event type={body.type} for user={user_id}")
    
    # Set user_id for tool and middleware (Phase 1 workaround)
    update_user_context._user_id = user_id
    set_middleware_user_id(user_id)
    
    # Generate thread_id
    thread_id = body.thread_id or "active"
    full_thread_id = f"user_{user_id}_thread_{thread_id}"
    
    # Convert event to system event message (HumanMessage format)
    # We use [SYSTEM EVENT] prefix so agent knows this is a structured event, not user text
    event_message = f"[SYSTEM EVENT] {json.dumps(body.model_dump())}"
    
    try:
        # Invoke agent with event message
        result = await agent.ainvoke(
            {"messages": [{"role": "user", "content": event_message}]},
            config={"configurable": {"thread_id": full_thread_id}}
        )
        
        # Extract response content
        last_msg = result["messages"][-1]
        response_content = ""
        if hasattr(last_msg, "content"):
            content = last_msg.content
            if isinstance(content, str):
                response_content = content
            elif isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        response_content += block.get("text", "")
                    elif isinstance(block, str):
                        response_content += block
        
        return {
            "status": "ok",
            "event_type": body.type,
            "response": response_content
        }
    except Exception as e:
        logger.error(f"[tool_event] Error processing event: {e}")
        return {
            "status": "error",
            "event_type": body.type,
            "error": str(e)
        }


@app.get("/health")
async def health():
    return {"status": "ok"}
