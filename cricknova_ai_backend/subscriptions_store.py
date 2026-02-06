import json
print("PRASAD72💕")
import os
from datetime import datetime, timedelta
import firebase_admin
from firebase_admin import auth
from fastapi import Header, HTTPException
from google.cloud import firestore

# -----------------------------
# FIREBASE INIT (SAFE GUARD)
# -----------------------------
if not firebase_admin._apps:
    try:
        # Render uses GOOGLE_APPLICATION_CREDENTIALS env automatically
        firebase_admin.initialize_app()
        print("🔥 FIREBASE ADMIN INITIALIZED (subscriptions_store)")
    except Exception as e:
        print("❌ FIREBASE INIT FAILED (subscriptions_store):", e)
        raise RuntimeError("Firebase Admin init failed")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FILE_PATH = os.path.join(BASE_DIR, "subscriptions.json")

# -----------------------------
# PLAN DEFINITIONS (SOURCE OF TRUTH)
# -----------------------------
PLAN_LIMITS = {
    "IN_99": {"chat": 200, "mistake": 15, "compare": 0},
    "IN_299": {"chat": 1200, "mistake": 30, "compare": 0},
    "IN_499": {"chat": 3000, "mistake": 60, "compare": 50},
    "IN_1999": {"chat": 20000, "mistake": 200, "compare": 200},

    "INT_MONTHLY": {"chat": 200, "mistake": 20, "compare": 0},
    "INT_6_MONTHS": {"chat": 1200, "mistake": 30, "compare": 5},
    "INT_YEARLY": {"chat": 1800, "mistake": 50, "compare": 10},
    "INT_ULTRA": {"chat": 20000, "mistake": 200, "compare": 150},
}

FREE_PLAN = {
    "plan": "free",
    "limits": {"chat": 5, "mistake": 2, "compare": 0},
    "chat_used": 0,
    "mistake_used": 0,
    "compare_used": 0,
    "expiry": None
}

# -----------------------------
# FILE HELPERS
# -----------------------------
def load_subscriptions():
    return {}

def save_subscriptions(data):
    return

# -----------------------------
# CORE LOGIC
# -----------------------------

def get_firestore_subscription(user_id: str):
    try:
        from google.cloud import firestore
        db = firestore.Client()
        doc = db.collection("subscriptions").document(user_id).get()
        if not doc.exists:
            return None
        return doc.to_dict()
    except Exception as e:
        print("❌ FIRESTORE READ FAILED:", e)
        return None
def get_subscription(user_id: str):
    # 🔥 Always prefer Firestore (single source of truth)
    fs_sub = get_firestore_subscription(user_id)
    if fs_sub:
        expiry = fs_sub.get("expiry")
        try:
            if hasattr(expiry, "to_datetime"):
                expiry_dt = expiry.to_datetime()
            elif isinstance(expiry, str):
                expiry_dt = datetime.fromisoformat(expiry)
            else:
                expiry_dt = None
        except Exception:
            expiry_dt = None
        fs_sub["_computed_active"] = expiry_dt is not None and datetime.utcnow() < expiry_dt
        return fs_sub

    return json.loads(json.dumps(FREE_PLAN))

def is_subscription_active(sub: dict) -> bool:
    if not sub:
        return False

    expiry = sub.get("expiry")
    try:
        if hasattr(expiry, "to_datetime"):
            expiry_dt = expiry.to_datetime()
        elif isinstance(expiry, str):
            expiry_dt = datetime.fromisoformat(expiry)
        else:
            return False
    except Exception:
        return False

    return datetime.utcnow() < expiry_dt

def check_limit_and_increment(user_id: str, feature: str):
    sub = get_subscription(user_id)

    if not sub or not sub.get("active"):
        return False, True  # premium required

    plan = sub.get("plan")
    if not plan or plan not in PLAN_LIMITS:
        return False, True

    limits = PLAN_LIMITS.get(plan, {})
    limit = limits.get(feature, 0)

    used_key = f"{feature}_used"
    used = int(sub.get(used_key, 0))

    if used >= limit:
        return False, True  # limit exceeded

    sub[used_key] = used + 1

    save_firestore_subscription(user_id, sub)

    return True, False

def create_or_update_subscription(user_id: str, plan: str, payment_id: str, order_id: str):
    plan_raw = str(plan).upper()
    if plan_raw.isdigit():
        plan = f"IN_{plan_raw}"
    else:
        plan = plan_raw
    if plan not in PLAN_LIMITS:
        raise ValueError(f"Invalid plan: {plan}")

    now = datetime.utcnow()
    # Determine duration_days based on plan type (assuming 30 days for monthly, etc.)
    # Since PLAN_LIMITS doesn't have duration_days, let's default to 30 days for simplicity
    duration_days = 30
    if plan in ["IN_299", "INT_6_MONTHS"]:
        duration_days = 180
    elif plan in ["IN_499", "INT_YEARLY"]:
        duration_days = 365
    elif plan in ["IN_1999", "INT_ULTRA"]:
        duration_days = 365

    expiry = now + timedelta(days=duration_days)

    data = {
        "user_id": user_id,
        "plan": plan,
        "isPremium": True,
        "limits": PLAN_LIMITS[plan],
        "chat_used": 0,
        "mistake_used": 0,
        "compare_used": 0,
        "payment_id": payment_id,
        "order_id": order_id,
        "started_at": now.isoformat(),
        "expiry": firestore.Timestamp.from_datetime(expiry)
    }

    save_firestore_subscription(user_id, data)
    return {
        "success": True,
        "status": "verified",
        "plan": plan,
        "user_id": user_id,
    }

# -----------------------------
# USAGE COUNTERS
# -----------------------------
def increment_chat(user_id: str):
    ok, premium_required = check_limit_and_increment(user_id, "chat")
    if not ok:
        if premium_required:
            raise ValueError("PREMIUM_REQUIRED")
        raise ValueError("CHAT_LIMIT_EXCEEDED")
    return True

def increment_mistake(user_id: str):
    ok, premium_required = check_limit_and_increment(user_id, "mistake")
    if not ok:
        if premium_required:
            raise ValueError("PREMIUM_REQUIRED")
        raise ValueError("MISTAKE_LIMIT_EXCEEDED")
    return True

def increment_compare(user_id: str):
    ok, premium_required = check_limit_and_increment(user_id, "compare")
    if not ok:
        if premium_required:
            raise ValueError("PREMIUM_REQUIRED")
        raise ValueError("COMPARE_LIMIT_EXCEEDED")
    return True

# -----------------------------
# AUTH HELPER (HARDENED)
# -----------------------------
def get_current_user(
    authorization: str | None = Header(default=None),
):
    """
    Resolve authenticated Firebase user.
    Rules:
    - Firebase ID token is mandatory
    - Accepts: 'Authorization: Bearer <token>'
    - Returns Firebase UID
    """

    if not authorization:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    try:
        auth_header = authorization.strip()

        # Accept both "Bearer <token>" and raw token (fallback)
        if auth_header.lower().startswith("bearer "):
            token = auth_header.split(" ", 1)[1].strip()
        else:
            token = auth_header

        # Basic JWT sanity check
        if not token or token.count(".") != 2:
            raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

        # Verify Firebase ID token (do NOT revoke-check to avoid false negatives)
        decoded = auth.verify_id_token(token, check_revoked=False)

        uid = decoded.get("uid")
        if not uid:
            raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

        return uid

    except Exception as e:
        print("❌ FIREBASE TOKEN VERIFY FAILED:", str(e))
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

def save_firestore_subscription(user_id: str, data: dict):
    """
    Persist subscription back to Firestore.
    Firestore schema is NOT modified.
    """
    from google.cloud import firestore
    db = firestore.Client()
    db.collection("subscriptions").document(user_id).set({
        **data,
        "isPremium": True,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }, merge=True)