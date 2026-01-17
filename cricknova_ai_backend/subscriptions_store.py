import json
import os
from datetime import datetime, timedelta

# -----------------------------
# PAYMENT STATUS STORE (TEMP)
# -----------------------------
PAYMENT_SUCCESS = "success"
PAYMENT_PENDING = "pending"
PAYMENT_FAILED = "failed"

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FILE_PATH = os.path.join(BASE_DIR, "subscriptions.json")

# -----------------------------
# PLAN DEFINITIONS (SOURCE OF TRUTH)
# -----------------------------
PLANS = {
    # -------- INDIA PLANS --------
    "IN_99": {
        "duration_days": 30,
        "limits": {"chat": 200, "mistake": 15, "compare": 0}
    },
    "IN_299": {
        "duration_days": 180,
        "limits": {"chat": 1200, "mistake": 30, "compare": 0}
    },
    "IN_499": {
        "duration_days": 365,
        "limits": {"chat": 3000, "mistake": 60, "compare": 50}
    },
    "IN_1999": {
        "duration_days": 365,
        "limits": {"chat": 20000, "mistake": 200, "compare": 200}
    },

    # -------- INTERNATIONAL PLANS --------
    "INTL_MONTHLY": {
        "duration_days": 30,
        "limits": {"chat": 200, "mistake": 20, "compare": 0}
    },
    "INTL_6M": {
        "duration_days": 180,
        "limits": {"chat": 1200, "mistake": 30, "compare": 5}
    },
    "INTL_YEARLY": {
        "duration_days": 365,
        "limits": {"chat": 1800, "mistake": 50, "compare": 10}
    },
    "INTL_ULTRA": {
        "duration_days": 365,
        "limits": {"chat": 20000, "mistake": 200, "compare": 150}
    },
    "ultra_pro": {
        "duration_days": 365,
        "limits": {"chat": 20000, "mistake": 200, "compare": 150}
    }
}

FREE_PLAN = {
    "plan": "free",
    "active": False,
    "limits": {"chat": 0, "mistake": 0, "compare": 0},
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
    # DEV override for local / Swagger / curl testing
    if user_id == "debug-user":
        return {
            "user_id": "debug-user",
            "plan": "ultra_pro",
            "active": True,
            "limits": {"chat": 9999, "mistake": 999, "compare": 999},
            "chat_used": 0,
            "mistake_used": 0,
            "compare_used": 0,
            "expiry": "2099-01-01T00:00:00"
        }
    subs = load_subscriptions()
    sub = subs.get(user_id)

    if not sub:
        sub = FREE_PLAN.copy()
        sub["user_id"] = user_id
        return sub

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
# PAYMENT VERIFICATION
# -----------------------------
def verify_payment_and_activate(
    user_id: str,
    plan: str,
    order_id: str,
    payment_id: str,
    payment_status: str
):
    """
    Backend-only source of truth.
    Activate subscription ONLY if payment_status == success
    """

    if payment_status != PAYMENT_SUCCESS:
        return {
            "status": payment_status,
            "activated": False
        }

    sub = create_or_update_subscription(
        user_id=user_id,
        plan=plan,
        payment_id=payment_id,
        order_id=order_id
    )

    return {
        "status": PAYMENT_SUCCESS,
        "activated": True,
        "subscription": sub
    }

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

    # fallback to debug user when auth is missing
    if not authorization:
        return "debug-user"

    try:
        parts = authorization.split(" ")
        if len(parts) == 2 and parts[1]:
            return parts[1]
    except Exception:
        pass

    return "debug-user"