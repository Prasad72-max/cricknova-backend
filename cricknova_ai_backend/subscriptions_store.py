import json
import os
from datetime import datetime, timedelta
import firebase_admin
from firebase_admin import auth

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
    "active": False,
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
    if not os.path.exists(FILE_PATH):
        return {}
    try:
        with open(FILE_PATH, "r") as f:
            return json.load(f)
    except Exception:
        return {}

def save_subscriptions(data):
    tmp_path = FILE_PATH + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp_path, FILE_PATH)

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
        if expiry:
            try:
                expiry_dt = datetime.fromisoformat(expiry)
                fs_sub["active"] = datetime.utcnow() < expiry_dt
            except Exception:
                fs_sub["active"] = False
        else:
            fs_sub["active"] = False
        return fs_sub

    # ⛔ fallback only if Firestore missing (should not happen in prod)
    subs = load_subscriptions()
    sub = subs.get(user_id)
    if not sub:
        return json.loads(json.dumps(FREE_PLAN))
    return sub

def is_subscription_active(sub: dict) -> bool:
    if not sub:
        return False
    if not sub.get("active", False):
        return False
    if not isinstance(sub.get("limits"), dict):
        return False
    return True

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

    subs = load_subscriptions()
    subs[user_id] = sub
    save_subscriptions(subs)
    save_firestore_subscription(user_id, sub)

    return True, False

def create_or_update_subscription(user_id: str, plan: str, payment_id: str, order_id: str):
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

    subs = load_subscriptions()
    subs[user_id] = {
        "user_id": user_id,
        "plan": plan,
        "active": True,
        "limits": PLAN_LIMITS[plan],
        "chat_used": 0,
        "mistake_used": 0,
        "compare_used": 0,
        "payment_id": payment_id,
        "order_id": order_id,
        "started_at": now.isoformat(),
        "expiry": expiry.isoformat()
    }

    save_subscriptions(subs)
    save_firestore_subscription(user_id, subs[user_id])
    return subs[user_id]

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
    authorization: str | None = None,
):
    """
    Resolve authenticated Firebase user.
    Rules:
    - Firebase ID token is mandatory
    - Accepts both: 'Bearer <token>' and '<token>'
    - Always returns Firebase UID
    """

    if not authorization:
        raise ValueError("USER_NOT_AUTHENTICATED")

    try:
        auth_header = authorization.strip()

        if auth_header.lower().startswith("bearer "):
            token = auth_header.split(" ", 1)[1].strip()
        else:
            token = auth_header

        if not token or token.count(".") != 2:
            raise ValueError("MALFORMED_TOKEN")

        decoded = auth.verify_id_token(token)
        uid = decoded.get("uid")

        if not uid:
            raise ValueError("UID_MISSING")

        return uid

    except Exception as e:
        print("❌ FIREBASE TOKEN VERIFY FAILED:", str(e))
        raise ValueError("USER_NOT_AUTHENTICATED")

def save_firestore_subscription(user_id: str, data: dict):
    """
    Persist subscription back to Firestore.
    Firestore schema is NOT modified.
    """
    from google.cloud import firestore
    db = firestore.Client()
    db.collection("subscriptions").document(user_id).set(data, merge=True)