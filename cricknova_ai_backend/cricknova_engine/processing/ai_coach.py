from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
from datetime import datetime
import os
from google.cloud import firestore
from gemini_text import generate_text

router = APIRouter()

db = None

def get_db():
    global db
    if db is None:
        try:
            db = firestore.Client()
            print("🔥 FIRESTORE CONNECTED OK (ai_coach)")
        except Exception as e:
            print("❌ FIRESTORE INIT FAILED (ai_coach):", e)
            raise RuntimeError(f"Firestore init failed: {e}")
    return db

PLAN_LIMITS = {
    "FREE": 5,   # allow limited free trial chats
    "IN_99": 200,
    "IN_299": 1200,
    "IN_499": 3000,
    "IN_1999": 5000,
    "INT_ULTRA": 7000,
    "INTL_ULTRA": 7000,
}

# -----------------------------
# TEMP OVERRIDE FLAG
# -----------------------------
ALLOW_FREE_AI = os.getenv("ALLOW_FREE_AI", "false").lower() == "true"

# -----------------------------
# REQUEST MODEL
# -----------------------------
class CoachRequest(BaseModel):
    user_id: str | None = None
    message: str | None = None
    history: list[dict] | None = None
    role: str = "player"

# -----------------------------
# HELPER TO GET PLAN FROM ENV / DB (TEMP SAFE FIX)
# -----------------------------
def get_user_plan(user_id: str) -> str:
    """
    SINGLE SOURCE OF TRUTH
    ----------------------
    Premium status is read ONLY from Firestore.
    FREE users are strictly blocked.
    """

    try:
        db_client = get_db()
        if not db_client:
            return "FREE"

        doc = db_client.collection("subscriptions").document(user_id).get()

        if not doc.exists:
            return "FREE"

        data = doc.to_dict() or {}

        expiry = data.get("expiry") or data.get("expiryDate") or data.get("expiry_date")
        plan = data.get("plan") or data.get("plan_id") or "FREE"
        print("🧾 SUBSCRIPTION DATA:", {"user_id": user_id, "plan": plan, "expiry": expiry})

        if not expiry or not plan:
            return "FREE"

        try:
            expiry_dt = datetime.fromisoformat(expiry.replace("Z", ""))
        except Exception:
            print("⚠️ INVALID EXPIRY FORMAT, treating as FREE:", expiry)
            return "FREE"

        if datetime.utcnow() > expiry_dt:
            return "FREE"

        return plan

    except Exception as e:
        print("❌ get_user_plan error:", e)
        raise HTTPException(
            status_code=500,
            detail="FIRESTORE_OR_SUBSCRIPTION_ERROR"
        )

# -----------------------------
# LIMIT CHECK
# -----------------------------
def check_chat_limit(user_id: str):
    db_client = get_db()
    doc = db_client.collection("subscriptions").document(user_id).get()

    if not doc.exists:
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    sub = doc.to_dict() or {}

    # ---- EXPIRY CHECK (support all field names) ----
    expiry = (
        sub.get("expiry")
        or sub.get("expiryDate")
        or sub.get("expiry_date")
    )

    if not expiry:
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    try:
        expiry_dt = datetime.fromisoformat(expiry.replace("Z", ""))
    except Exception:
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    if datetime.utcnow() > expiry_dt:
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    plan = sub.get("plan")
    limits = sub.get("limits", {})
    chat_limit = limits.get("chat", 0)

    used = sub.get("chat_used", 0)

    if not plan or chat_limit <= 0:
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    if used >= chat_limit:
        raise HTTPException(status_code=403, detail="CHAT_LIMIT_REACHED")

    # increment usage atomically
    db_client.collection("subscriptions").document(user_id).update({
        "chat_used": firestore.Increment(1)
    })

    return {
        "used": used + 1,
        "limit": chat_limit,
        "remaining": chat_limit - (used + 1)
    }

# -----------------------------
# AI COACH ENDPOINT
# -----------------------------
@router.post("/coach/chat")
async def ai_coach(req: CoachRequest, request: Request):
    # 🔐 Resolve authenticated user (robust multi-source)
    user_id = (
        req.user_id
        or request.headers.get("x-user-id")
        or request.headers.get("X-User-Id")
        or getattr(request.state, "user_id", None)
    )

    print("🔐 RESOLVED USER_ID:", user_id)
    print("📦 HEADERS:", dict(request.headers))

    if not user_id:
        raise HTTPException(
            status_code=401,
            detail="USER_NOT_AUTHENTICATED"
        )

    if not req.message or not req.message.strip():
        return {"reply": "Ask a cricket-related question."}

    # ❗ AI CONFIG CHECK (do this BEFORE usage / premium checks)
    if not (os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")):
        print("❌ GEMINI_API_KEY missing on server")
        return {
            "reply": "AI Coach is temporarily unavailable. Please try again later."
        }

    # 🔐 LIMIT CHECK (only after AI is ready)
    limit_info = check_chat_limit(user_id)

    try:
        history_lines = []
        for item in (req.history or [])[-8:]:
            if not isinstance(item, dict):
                continue
            role = str(item.get("role", "user")).strip().lower()
            content = str(item.get("content", "")).strip()
            if not content:
                continue
            prefix = "User" if role == "user" else "Coach"
            history_lines.append(f"{prefix}: {content}")

        history_block = "\n".join(history_lines).strip()

        prompt = f"""
You are an elite professional cricket coach.

Answer the user's actual question in natural coaching language.
Do not force a fixed numbered template unless the user asks for bullet points.
Do not sound scripted, robotic, or repetitive.

Rules:
- Answer only cricket-related questions.
- If the question is not about cricket, politely refuse in 1 short sentence and ask for a cricket question.
- If the user asks about batting, answer batting.
- If the user asks about bowling, answer bowling.
- If the user asks about mindset, match situations, training, fitness for cricket, or fielding, answer naturally.
- If the question is vague, ask 1 short follow-up or give neutral cricket coaching instead of assuming bowling.
- Be honest, practical, and technical when needed.
- No fake clip analysis if no clip context is provided.
- No unnecessary headings.
- Keep it realistic like a real coach.
- Use recent chat history only to keep continuity for follow-up questions like "give tips", "what next", or "why".
- If the latest user question changes topic, answer the latest topic directly.

Recent chat history:
{history_block if history_block else "No previous chat context."}

Situation / Question:
{req.message}
"""

        reply = generate_text(
            system_instruction="You are an elite professional cricket coach.",
            user_prompt=prompt,
            temperature=0.72,
            max_output_tokens=220,
        )

        return {
            "reply": reply,
            "usage": limit_info,
            "plan": get_user_plan(user_id)
        }

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"AI Coach error: {str(e)}"
        )
