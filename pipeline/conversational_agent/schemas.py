from pydantic import BaseModel


class ChatRequestBody(BaseModel):
    message: str
    thread_id: str | None = None
