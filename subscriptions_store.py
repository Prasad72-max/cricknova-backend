import json
import os
from datetime import datetime, timedelta

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
def get_subscription(user_id: str):
    subs = load_subscriptions()
    sub = subs.get(user_id)

    if not sub:
        return FREE_PLAN.copy()

    expiry = sub.get("expiry")
    if not expiry:
        sub["active"] = False
        return sub

    try:
        expiry_dt = datetime.fromisoformat(expiry)
    except Exception:
        sub["active"] = False
        return sub

    if datetime.utcnow() >= expiry_dt:
        sub["active"] = False
    else:
        sub["active"] = True

    return sub

def is_subscription_active(sub: dict) -> bool:
    if not sub:
        return False
    if not sub.get("active"):
        return False
    if not sub.get("limits"):
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
    return subs[user_id]

# -----------------------------
# USAGE COUNTERS
# -----------------------------
def increment_chat(user_id: str):
    subs = load_subscriptions()
    sub = subs.get(user_id)
    if not sub:
        return

    limit = sub.get("limits", {}).get("chat", 0)
    used = sub.get("chat_used", 0)

    if used >= limit:
        return

    sub["chat_used"] = used + 1
    save_subscriptions(subs)

def increment_mistake(user_id: str):
    subs = load_subscriptions()
    sub = subs.get(user_id)
    if not sub:
        return

    limit = sub.get("limits", {}).get("mistake", 0)
    used = sub.get("mistake_used", 0)

    if used >= limit:
        return

    sub["mistake_used"] = used + 1
    save_subscriptions(subs)

def increment_compare(user_id: str):
    subs = load_subscriptions()
    sub = subs.get(user_id)
    if not sub:
        return

    limit = sub.get("limits", {}).get("compare", 0)
    used = sub.get("compare_used", 0)

    if used >= limit:
        return

    sub["compare_used"] = used + 1
    save_subscriptions(subs)

# -----------------------------
# AUTH HELPER (TEMPORARY)
# -----------------------------
def get_current_user(authorization: str | None = None):
    """
    Extract user_id from Authorization header.
    Expected format: "Bearer <USER_ID>"
    """

    if not authorization:
        return None

    try:
        parts = authorization.split(" ")
        if len(parts) == 2 and parts[1]:
            return parts[1]
    except Exception:
        pass

    return None

def save_firestore_subscription(user_id: str, data: dict):
    """
    Persist subscription back to Firestore.
    Firestore schema is NOT modified.
    """
    from google.cloud import firestore
    db = firestore.Client()
    db.collection("subscriptions").document(user_id).set(data, merge=True)

def check_limit_and_increment(user_id: str, feature: str):
    sub = get_subscription(user_id)

    # Not active or no subscription
    if not sub or not sub.get("active"):
        return False, True  # premium required

    plan = sub.get("plan")
    if not plan or plan not in PLAN_LIMITS:
        return False, True

    limits = PLAN_LIMITS.get(plan, {})
    limit = limits.get(feature, 0)

    used_key = f"{feature}_used"
    used = int(sub.get(used_key, 0))

    # Limit exceeded
    if used >= limit:
        return False, True

    # Increment usage
    sub[used_key] = used + 1

    # Persist back to Firestore
    save_firestore_subscription(user_id, sub)

    return True, False