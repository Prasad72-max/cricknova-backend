from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
from openai import OpenAI
from datetime import datetime
import os
from google.cloud import firestore
from cricknova_ai_backend.subscriptions_store import get_current_user

# 🔧 TEMP DEBUG FLAGS (Render stability)
BYPASS_AUTH = os.getenv("BYPASS_AUTH", "false").lower() == "true"

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

# -----------------------------
# OPENAI CLIENT
# -----------------------------
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    OPENAI_API_KEY = None

client = OpenAI(api_key=OPENAI_API_KEY)

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
    role: str = "batsman"

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
def check_limit(user_id: str, feature: str):
    db_client = get_db()
    doc = db_client.collection("subscriptions").document(user_id).get()

    if not doc.exists:
        return False, True, {
            "used": 0,
            "limit": 0,
            "remaining": 0
        }

    sub = doc.to_dict() or {}
    print("🧪 RESTORE DEBUG → raw subscription data:", sub)

    expiry = (
        sub.get("expiry")
        or sub.get("expiryDate")
        or sub.get("expiry_date")
    )

    if not expiry:
        return False, True, {
            "used": sub.get(f"{feature}_used", 0),
            "limit": 0,
            "remaining": 0
        }

    try:
        expiry_dt = datetime.fromisoformat(expiry.replace("Z", ""))
    except Exception:
        return False, True, {
            "used": sub.get(f"{feature}_used", 0),
            "limit": 0,
            "remaining": 0
        }

    if datetime.utcnow() > expiry_dt:
        return False, True, {
            "used": sub.get(f"{feature}_used", 0),
            "limit": 0,
            "remaining": 0
        }

    raw_plan = (sub.get("plan") or "").upper().strip()

    PLAN_LIMITS = {
        "IN_99": {"chat": 200, "mistake": 15},
        "IN_299": {"chat": 1200, "mistake": 30},
        "IN_499": {"chat": 3000, "mistake": 60},
        "IN_1999": {"chat": 20000, "mistake": 200},
        "MONTHLY": {"chat": 200, "mistake": 15},
        "6 MONTHS": {"chat": 1200, "mistake": 30},
        "YEARLY": {"chat": 3000, "mistake": 60},
        "ULTRA": {"chat": 20000, "mistake": 200},
        "ULTRA PRO": {"chat": 20000, "mistake": 200},
    }

    limits = PLAN_LIMITS.get(raw_plan)
    print("🧪 RESTORE DEBUG → limits found:", limits)
    if not limits:
        return False, True, {
            "used": sub.get(f"{feature}_used", 0),
            "limit": 0,
            "remaining": 0
        }

    limit = limits.get(feature)
    used_key = f"{feature}_used"
    used = sub.get(used_key, 0)
    print(
        "🧪 RESTORE DEBUG → feature:", feature,
        "| used:", used,
        "| limit:", limit
    )

    if used >= limit:
        return False, True, {
            "used": used,
            "limit": limit,
            "remaining": 0
        }

    db_client.collection("subscriptions").document(user_id).set(
        {used_key: firestore.Increment(1)},
        merge=True
    )

    return True, False, {
        "used": used + 1,
        "limit": limit,
        "remaining": limit - (used + 1)
    }

# -----------------------------
# AI COACH ENDPOINT
# -----------------------------
@router.post("/coach/chat")
async def ai_coach(
    req: CoachRequest,
    request: Request,
    skip_limit: bool = False
):
    # 🔐 Resolve authenticated user (robust multi-source)
    user_id = None

    # 1️⃣ Try Authorization header (Firebase ID token)
    if not BYPASS_AUTH:
        user_id = get_current_user(
            authorization=request.headers.get("Authorization"),
            x_user_id=request.headers.get("X-USER-ID")
        )

    # 2️⃣ Fallback: accept user_id from request body (frontend safety net)
    if not user_id and req.user_id:
        user_id = req.user_id

    print("🔐 RESOLVED USER_ID:", user_id)
    print("📦 HEADERS:", dict(request.headers))
    print("🧪 BYPASS_AUTH:", BYPASS_AUTH)

    if not user_id and not BYPASS_AUTH:
        return {
            "reply": "Authentication issue detected. Please reopen the app and try again.",
            "coach_feedback": "Authentication issue detected. Please reopen the app and try again."
        }

    # fallback dummy user for AI testing
    if BYPASS_AUTH and not user_id:
        user_id = "render-test-user"

    if not req.message or not req.message.strip():
        return {"reply": "Ask a cricket-related question."}

    # ❗ AI CONFIG CHECK (do this BEFORE usage / premium checks)
    if not OPENAI_API_KEY:
        print("❌ OPENAI_API_KEY missing on server")
        return {
            "reply": "AI Coach is temporarily unavailable. Please try again later.",
            "coach_feedback": "AI Coach is temporarily unavailable. Please try again later."
        }

    # 🔐 LIMIT CHECK (only after AI is ready)
    limit_info = None
    if not skip_limit:
        allowed, premium_required, limit_info = check_limit(user_id, feature="chat")
        if not allowed:
            return {
                "success": False,
                "error": "LIMIT_EXCEEDED",
                "premium_required": premium_required
            }

    prompt = f"""
You are an elite professional cricket coach.

Analyze the situation and explicitly identify:
- Ball SPEED
- Ball SWING
- Ball SPIN

If any value is not applicable, infer it realistically. Never return "unknown".

Give output in the EXACT format below.

BALL METRICS:
Speed:
Swing:
Spin:

BATSMAN ANALYSIS:
Mistake:
- One clear, technical batting mistake

Improvement:
- One practical batting improvement or drill

BOWLER ANALYSIS:
Mistake:
- One clear bowling mistake related to line, length, pace, swing or spin

Improvement:
- One practical bowling improvement or adjustment

Rules:
- Be honest and technical
- No motivation talk
- No extra explanations
- Keep it realistic like a real coach

Situation / Question:
{req.message}
"""

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.4,
            max_tokens=180
        )

        return {
            "success": True,
            "reply": response.choices[0].message.content.strip(),
            "usage": limit_info,
            "plan": get_user_plan(user_id),
            "premium_required": False
        }

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"AI Coach error: {str(e)}"
        )

# -----------------------------
# FRONTEND COMPATIBILITY ENDPOINT
# -----------------------------
@router.post("/coach/analyze")
async def ai_coach_analyze(req: CoachRequest, request: Request):
    """
    Compatibility wrapper for older frontend builds.
    Internally routes to /coach/chat logic.
    """

    # 🔐 LIMIT CHECK for mistake feature
    user_id = None

    # 1️⃣ Try Authorization header (Firebase ID token)
    if not BYPASS_AUTH:
        user_id = get_current_user(
            authorization=request.headers.get("Authorization"),
            x_user_id=request.headers.get("X-USER-ID")
        )

    # 2️⃣ Fallback: accept user_id from request body (frontend safety net)
    if not user_id and req.user_id:
        user_id = req.user_id

    if not user_id and not BYPASS_AUTH:
        return {
            "coach_feedback": "Authentication issue detected. Please reopen the app and try again.",
            "reply": "Authentication issue detected. Please reopen the app and try again.",
            "usage": None,
            "plan": "FREE"
        }

    if BYPASS_AUTH and not user_id:
        user_id = "render-test-user"

    allowed, premium_required, limit_info = check_limit(user_id, feature="chat")
    if not allowed:
        return {
            "success": False,
            "error": "LIMIT_EXCEEDED",
            "premium_required": premium_required
        }

    response = await ai_coach(req, request, skip_limit=True)

    # Ensure frontend always gets expected keys
    return {
        "coach_feedback": response.get("reply"),
        "reply": response.get("reply"),
        "usage": limit_info,
        "plan": response.get("plan"),
    }