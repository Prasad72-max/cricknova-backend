from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, Dict
from datetime import datetime
from datetime import timedelta

# ⚠️ IMPORTANT:
# This backend file is the single source of truth for mistake limits.
# Frontend plan flags are NOT trusted.
# Any request reaching this file without a valid paid plan MUST be blocked.

router = APIRouter()

# -----------------------------
# SHARED PLAN CONFIG (SOURCE OF TRUTH)
# -----------------------------
PLAN_LIMITS = {
    "IN_99": {
        "mistake_limit": 15,
        "duration_days": 30,
    },
    "IN_299": {
        "mistake_limit": 30,
        "duration_days": 180,
    },
    "IN_599": {
        "mistake_limit": 60,
        "duration_days": 365,
    },
    "IN_2999": {
        "mistake_limit": 200,
        "duration_days": 365,
    },
}

# -----------------------------
# REQUEST MODEL
# -----------------------------
class MistakeRequest(BaseModel):
    user_id: str

USER_MISTAKE_STATE: Dict[str, Dict] = {}

# -----------------------------
# RESPONSE MODELS
# -----------------------------
class MistakeResponse(BaseModel):
    status: str
    mistakes_detected: int
    remaining: int


class MistakeUsageResponse(BaseModel):
    used: int
    limit: int
    remaining: int

# -----------------------------
# INTERNAL LIMIT CHECK
# -----------------------------
def check_and_increment_mistake(user_id: str):
    user = USER_MISTAKE_STATE.get(user_id)

    # 🚫 HARD BLOCK: No plan = FREE user = no AI access
    if not user or "plan" not in user:
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    plan = user["plan"]

    # 🚫 Explicit FREE / invalid plan block
    if plan not in PLAN_LIMITS:
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    limits = PLAN_LIMITS[plan]

    now = datetime.utcnow()

    if now >= datetime.fromisoformat(user["expiry"]):
        raise HTTPException(status_code=403, detail="PLAN_EXPIRED")

    if user["mistake_used"] >= limits["mistake_limit"]:
        raise HTTPException(status_code=403, detail="MISTAKE_LIMIT_REACHED")

    user["mistake_used"] += 1
    user["last_used"] = now.isoformat()
    USER_MISTAKE_STATE[user_id] = user
    return user

# -----------------------------
# MISTAKE DETECTION ENDPOINT
# -----------------------------
@router.post("/mistake/detect", response_model=MistakeResponse)
async def detect_mistake(req: MistakeRequest):
    # 🔐 Backend-enforced premium check
    usage = check_and_increment_mistake(req.user_id)

    return {
        "status": "success",
        "mistakes_detected": 1,
        "remaining": PLAN_LIMITS[usage["plan"]]["mistake_limit"] - usage["mistake_used"],
    }

# -----------------------------
# USAGE STATUS ENDPOINT
# -----------------------------
@router.get("/mistake/usage/{user_id}", response_model=MistakeUsageResponse)
async def get_mistake_usage(user_id: str):
    usage = USER_MISTAKE_STATE.get(user_id)

    if not usage:
        raise HTTPException(status_code=404, detail="USAGE_NOT_FOUND")

    return {
        "used": usage["mistake_used"],
        "limit": PLAN_LIMITS[usage["plan"]]["mistake_limit"],
        "remaining": PLAN_LIMITS[usage["plan"]]["mistake_limit"] - usage["mistake_used"],
    }