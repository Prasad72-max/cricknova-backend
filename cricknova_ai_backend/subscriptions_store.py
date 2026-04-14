import json
import os
from datetime import datetime, timedelta, timezone

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FILE_PATH = os.path.join(BASE_DIR, "subscriptions.json")


def _parse_expiry(raw_expiry):
    if raw_expiry is None:
        return None
    if hasattr(raw_expiry, "to_datetime"):
        try:
            raw_expiry = raw_expiry.to_datetime()
        except Exception:
            return None
    if hasattr(raw_expiry, "isoformat") and not isinstance(raw_expiry, str):
        try:
            raw_expiry = raw_expiry.isoformat()
        except Exception:
            return None
    if isinstance(raw_expiry, str):
        value = raw_expiry.strip()
        if not value:
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except Exception:
            try:
                return datetime.fromisoformat(value.replace("Z", ""))
            except Exception:
                return None
    return None

# -----------------------------
# PLAN DEFINITIONS (SOURCE OF TRUTH)
# -----------------------------
PLANS = {
    "monthly": {
        "duration_days": 30,
        "limits": {"chat": 200, "mistake": 15, "compare": 0}
    },
    "6_months": {
        "duration_days": 180,
        "limits": {"chat": 1200, "mistake": 30, "compare": 0}
    },
    "yearly": {
        "duration_days": 365,
        "limits": {"chat": 3000, "mistake": 60, "compare": 50}
    },
    "ultra_pro": {
        "duration_days": 365,
        "limits": {"chat": 7000, "mistake": 150, "compare": 150}
    }
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

    expiry = _parse_expiry(sub.get("expiry"))
    if not expiry:
        return FREE_PLAN.copy()

    now = datetime.now(timezone.utc)
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=timezone.utc)

    if now >= expiry:
        return FREE_PLAN.copy()

    return sub

def is_subscription_active(sub: dict) -> bool:
    return bool(sub and sub.get("active") is True)

def create_or_update_subscription(user_id: str, plan: str, payment_id: str, order_id: str):
    if plan not in PLANS:
        raise ValueError(f"Invalid plan: {plan}")

    now = datetime.utcnow()
    plan_cfg = PLANS[plan]
    expiry = now + timedelta(days=plan_cfg["duration_days"])

    subs = load_subscriptions()
    subs[user_id] = {
        "user_id": user_id,
        "plan": plan,
        "active": True,
        "limits": plan_cfg["limits"],
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
    sub["chat_used"] += 1
    save_subscriptions(subs)

def increment_mistake(user_id: str):
    subs = load_subscriptions()
    sub = subs.get(user_id)
    if not sub:
        return
    sub["mistake_used"] += 1
    save_subscriptions(subs)

def increment_compare(user_id: str):
    subs = load_subscriptions()
    sub = subs.get(user_id)
    if not sub:
        return
    sub["compare_used"] += 1
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
        if len(parts) == 2:
            return parts[1]
    except Exception:
        pass

    return None
