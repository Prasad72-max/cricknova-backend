from fastapi import APIRouter, HTTPException
from datetime import datetime, timedelta

# 🔐 Backend is the single source of truth for subscription & limits.
# FREE users must NEVER consume AI usage.
# Frontend flags are not trusted.

router = APIRouter()

# -----------------------------
# PLAN CONFIG (single source)
# -----------------------------
PLANS = {
    "FREE": {
        "chat_limit": 0,
        "mistake_limit": 0,
        "compare_limit": 0,
        "duration_days": 0,
    },
    "IN_99": {   # Monthly
        "chat_limit": 200,
        "mistake_limit": 15,
        "compare_limit": 0,
        "duration_days": 30,
    },
    "IN_299": {  # 6 months
        "chat_limit": 1200,
        "mistake_limit": 30,
        "compare_limit": 0,
        "duration_days": 180,
    },
    "IN_499": {  # Yearly
        "chat_limit": 3000,
        "mistake_limit": 60,
        "compare_limit": 50,
        "duration_days": 365,
    },
    "IN_1999": { # Yearly Pro
        "chat_limit": 20000,
        "mistake_limit": 200,
        "compare_limit": 200,
        "duration_days": 365,
    },
}

# -----------------------------
# TEMP IN-MEMORY STORE
# (Replace later with DB)
# -----------------------------
USERS = {}

def get_user(user_id: str):
    if user_id not in USERS:
        USERS[user_id] = {
            "plan": "FREE",
            "chat_used": 0,
            "mistake_used": 0,
            "compare_used": 0,
            "expiry": None,
        }
    return USERS[user_id]

# -----------------------------
# SUBSCRIPTION STATUS
# -----------------------------
@router.get("/subscription/status")
def subscription_status(user_id: str):
    user = get_user(user_id)
    plan_cfg = PLANS[user["plan"]]

    return {
        "isPremium": user["plan"] != "FREE",
        "plan": user["plan"],
        "chat_remaining": max(plan_cfg["chat_limit"] - user["chat_used"], 0),
        "mistake_remaining": max(plan_cfg["mistake_limit"] - user["mistake_used"], 0),
        "compare_remaining": max(plan_cfg["compare_limit"] - user["compare_used"], 0),
        "expiry": user["expiry"],
    }

# -----------------------------
# ACTIVATE PLAN (after payment)
# -----------------------------
@router.post("/subscription/activate")
def activate_plan(user_id: str, plan: str):
    if plan not in PLANS:
        raise HTTPException(status_code=400, detail="Invalid plan")

    duration = PLANS[plan]["duration_days"]

    USERS[user_id] = {
        "plan": plan,
        "chat_used": 0,
        "mistake_used": 0,
        "compare_used": 0,
        "expiry": (datetime.utcnow() + timedelta(days=duration)).isoformat() if duration > 0 else None,
    }

    return {"status": "activated", "plan": plan}

# -----------------------------
# USAGE ENDPOINTS
# -----------------------------
@router.post("/use/chat")
def use_chat(user_id: str):
    user = get_user(user_id)

    # 🚫 HARD BLOCK: FREE users cannot use AI
    if user["plan"] == "FREE":
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    if user["expiry"] is not None:
        if datetime.utcnow() >= datetime.fromisoformat(user["expiry"]):
            raise HTTPException(status_code=403, detail="PLAN_EXPIRED")
    limit = PLANS[user["plan"]]["chat_limit"]

    if user["chat_used"] >= limit:
        raise HTTPException(status_code=403, detail="CHAT_LIMIT_REACHED")

    user["chat_used"] += 1
    return {"remaining": limit - user["chat_used"]}

@router.post("/use/mistake")
def use_mistake(user_id: str):
    user = get_user(user_id)

    # 🚫 HARD BLOCK: FREE users cannot use AI
    if user["plan"] == "FREE":
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    if user["expiry"] is not None:
        if datetime.utcnow() >= datetime.fromisoformat(user["expiry"]):
            raise HTTPException(status_code=403, detail="PLAN_EXPIRED")
    limit = PLANS[user["plan"]]["mistake_limit"]

    if user["mistake_used"] >= limit:
        raise HTTPException(status_code=403, detail="MISTAKE_LIMIT_REACHED")

    user["mistake_used"] += 1
    return {"remaining": limit - user["mistake_used"]}

@router.post("/use/compare")
def use_compare(user_id: str):
    user = get_user(user_id)

    # 🚫 HARD BLOCK: FREE users cannot use AI
    if user["plan"] == "FREE":
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    if user["expiry"] is not None:
        if datetime.utcnow() >= datetime.fromisoformat(user["expiry"]):
            raise HTTPException(status_code=403, detail="PLAN_EXPIRED")
    limit = PLANS[user["plan"]]["compare_limit"]

    if user["compare_used"] >= limit:
        raise HTTPException(status_code=403, detail="COMPARE_LIMIT_REACHED")

    user["compare_used"] += 1
    return {"remaining": limit - user["compare_used"]}