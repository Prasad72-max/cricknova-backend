from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from openai import OpenAI
from datetime import datetime
import os

router = APIRouter()

# -----------------------------
# OPENAI CLIENT
# -----------------------------
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    raise RuntimeError("OPENAI_API_KEY not set")

client = OpenAI(api_key=OPENAI_API_KEY)

# -----------------------------
# TEMP IN-MEMORY USAGE STORE
# -----------------------------
# user_id -> usage
USER_USAGE = {}

PLAN_LIMITS = {
    "FREE": 0,
    "IN_99": 200,
    "IN_299": 1200,
    "IN_499": 3000,
    "IN_1999": 20000,
}

# -----------------------------
# REQUEST MODEL
# -----------------------------
class CoachRequest(BaseModel):
    user_id: str
    message: str | None = None
    role: str = "batsman"

# -----------------------------
# HELPER TO GET PLAN FROM DB (STUB)
# -----------------------------
def get_user_plan(user_id: str) -> str:
    # TODO: replace with DB lookup
    # default FREE unless premium verified
    return USER_USAGE.get(user_id, {}).get("plan", "FREE")

# -----------------------------
# LIMIT CHECK
# -----------------------------
def check_chat_limit(user_id: str):
    plan = get_user_plan(user_id)

    if plan not in PLAN_LIMITS:
        raise HTTPException(status_code=403, detail="INVALID_PLAN")

    limit = PLAN_LIMITS[plan]

    if limit == 0:
        raise HTTPException(
            status_code=403,
            detail="PREMIUM_REQUIRED"
        )

    usage = USER_USAGE.get(user_id, {"chat": 0, "plan": plan})

    remaining = limit - usage["chat"]

    if remaining <= 0:
        raise HTTPException(
            status_code=403,
            detail="CHAT_LIMIT_REACHED"
        )

    usage["chat"] += 1
    usage["last_used"] = datetime.utcnow().isoformat()
    USER_USAGE[user_id] = usage

    return {
        "used": usage["chat"],
        "limit": limit,
        "remaining": limit - usage["chat"]
    }

# -----------------------------
# AI COACH ENDPOINT
# -----------------------------
@router.post("/coach/chat")
async def ai_coach(req: CoachRequest):
    if not req.message or not req.message.strip():
        return {"reply": "Ask a cricket-related question."}

    # 🔐 LIMIT CHECK
    limit_info = check_chat_limit(req.user_id)

    try:
        prompt = f"""
You are an elite cricket AI coach.
User role: {req.role}

Give practical, short, technical advice.
No motivation talk. Only technique and drills.

Question:
{req.message}
"""

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.4,
            max_tokens=180
        )

        return {
            "reply": response.choices[0].message.content.strip(),
            "usage": limit_info
        }

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"AI Coach error: {str(e)}"
        )