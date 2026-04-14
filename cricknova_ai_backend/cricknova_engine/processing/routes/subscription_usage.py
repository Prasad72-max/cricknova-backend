from fastapi import APIRouter, Request
from services.subscription import (
    increment_chat,
    increment_mistake,
    increment_compare,
)

router = APIRouter(prefix="/usage", tags=["usage"])

@router.post("/chat")
def use_chat(request: Request):
    user_id = request.headers.get("X-USER-ID")
    if not user_id:
        return {"error": "Missing user"}
    increment_chat(user_id)
    return {"ok": True}

@router.post("/mistake")
def use_mistake(request: Request):
    user_id = request.headers.get("X-USER-ID")
    if not user_id:
        return {"error": "Missing user"}
    increment_mistake(user_id)
    return {"ok": True}

@router.post("/compare")
def use_compare(request: Request):
    user_id = request.headers.get("X-USER-ID")
    if not user_id:
        return {"error": "Missing user"}
    increment_compare(user_id)
    return {"ok": True}