from fastapi import APIRouter, Request
from services.subscription import (
    increment_chat,
    increment_mistake,
    increment_compare,
)

router = APIRouter(prefix="/usage", tags=["usage"])

@router.post("/chat")
async def use_chat(request: Request):
    user_id = request.headers.get("X-USER-ID")
    if user_id:
        try:
            increment_chat(user_id)
        except Exception:
            pass
    return {"ok": True}

@router.post("/mistake")
async def use_mistake(request: Request):
    user_id = request.headers.get("X-USER-ID")
    if user_id:
        try:
            increment_mistake(user_id)
        except Exception:
            pass
    return {"ok": True}

@router.post("/compare")
async def use_compare(request: Request):
    user_id = request.headers.get("X-USER-ID")
    if user_id:
        try:
            increment_compare(user_id)
        except Exception:
            pass
    return {"ok": True}