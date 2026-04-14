from fastapi import APIRouter, Request, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from services.subscription import (
    increment_chat,
    increment_mistake,
    increment_compare,
)

router = APIRouter(prefix="/usage", tags=["usage"])

security = HTTPBearer(auto_error=False)

@router.post("/chat")
async def use_chat(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    user_id = credentials.credentials if credentials else None
    if user_id:
        try:
            increment_chat(user_id)
        except Exception:
            pass
    return {"ok": True}

@router.post("/mistake")
async def use_mistake(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    user_id = credentials.credentials if credentials else None
    if user_id:
        try:
            increment_mistake(user_id)
        except Exception:
            pass
    return {"ok": True}

@router.post("/compare")
async def use_compare(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    user_id = credentials.credentials if credentials else None
    if user_id:
        try:
            increment_compare(user_id)
        except Exception:
            pass
    return {"ok": True}