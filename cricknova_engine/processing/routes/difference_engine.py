from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime
from typing import Dict

# 🔐 Backend is the single source of truth for plan & limits.
# FREE users must NEVER access Diff / Video Compare.
# Frontend flags are NOT trusted.

router = APIRouter()

# -----------------------------
# SHARED PLAN CONFIG (SOURCE OF TRUTH)
# -----------------------------
PLAN_LIMITS = {
    "IN_99": {
        "compare_limit": 0,
        "duration_days": 30,
    },
    "IN_299": {
        "compare_limit": 0,
        "duration_days": 180,
    },
    "IN_599": {
        "compare_limit": 50,
        "duration_days": 365,
    },
    "IN_2999": {
        "compare_limit": 200,
        "duration_days": 365,
    },
}

# -----------------------------
# IN-MEMORY USAGE STORE
# (replace with DB later)
# -----------------------------
USER_COMPARE_STATE: Dict[str, Dict] = {}

# -----------------------------
# REQUEST MODEL
# -----------------------------
class DifferenceRequest(BaseModel):
    user_id: str

# -----------------------------
# RESPONSE MODEL
# -----------------------------
class DifferenceResponse(BaseModel):
    status: str
    remaining: int
    differences_found: int

# -----------------------------
# LIMIT CHECK
# -----------------------------
def check_and_increment_compare(user_id: str):
    user = USER_COMPARE_STATE.get(user_id)

    # 🚫 HARD BLOCK: no plan or FREE user
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

    if limits["compare_limit"] == 0:
        raise HTTPException(status_code=403, detail="PLAN_HAS_NO_VIDEO_COMPARE")

    if user["compare_used"] >= limits["compare_limit"]:
        raise HTTPException(status_code=403, detail="COMPARE_LIMIT_REACHED")

    user["compare_used"] += 1
    user["last_used"] = now.isoformat()
    USER_COMPARE_STATE[user_id] = user

    return user

# -----------------------------
# DIFFERENCE / VIDEO COMPARE API
# -----------------------------
@router.post("/difference/compare", response_model=DifferenceResponse)
async def compare_videos(req: DifferenceRequest):
    usage = check_and_increment_compare(req.user_id)

    differences_found = 3

    return {
        "status": "success",
        "remaining": PLAN_LIMITS[usage["plan"]]["compare_limit"] - usage["compare_used"],
        "differences_found": differences_found,
    }