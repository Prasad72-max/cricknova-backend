from fastapi import APIRouter, HTTPException, Request, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from datetime import datetime, timedelta
from google.cloud import firestore
from pydantic import BaseModel
from cricknova_engine.processing.firebase_init import verify_firebase_token

# 🔐 Backend is the single source of truth for subscription & limits.
# Uses Firestore for persistence (NO in-memory loss)

router = APIRouter()
security = HTTPBearer(auto_error=False)
_db = None

class ActivatePlanRequest(BaseModel):
    plan: str

def get_db():
    global _db
    if _db is None:
        try:
            _db = firestore.Client()
        except Exception as e:
            print("❌ Firestore init failed:", e)
            return None
    return _db

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
    "IN_99": {
        "chat_limit": 200,
        "mistake_limit": 15,
        "compare_limit": 0,
        "duration_days": 30,
    },
    "IN_299": {
        "chat_limit": 1200,
        "mistake_limit": 30,
        "compare_limit": 0,
        "duration_days": 180,
    },
    "IN_499": {
        "chat_limit": 3000,
        "mistake_limit": 60,
        "compare_limit": 50,
        "duration_days": 365,
    },
    "IN_1999": {
        "chat_limit": 5000,
        "mistake_limit": 150,
        "compare_limit": 150,
        "duration_days": 365,
    },
    "INT_ULTRA": {
        "chat_limit": 7000,
        "mistake_limit": 150,
        "compare_limit": 150,
        "duration_days": 365,
    },
}

PLAN_ALIASES = {
    "monthly": "IN_99",
    "6_months": "IN_299",
    "yearly": "IN_499",
    "ultra_pro": "IN_1999",
    "INTL_MONTHLY": "IN_99",
    "INTL_6M": "IN_299",
    "INTL_YEARLY": "IN_499",
    "INTL_ULTRA": "INT_ULTRA",
    "INT_ULTRA": "INT_ULTRA",
}


def _normalize_plan(raw_plan) -> str:
    if raw_plan is None:
        return "FREE"
    plan = str(raw_plan).strip()
    if not plan:
        return "FREE"
    return PLAN_ALIASES.get(plan.lower(), plan.upper())


def _parse_expiry(raw_expiry):
    if raw_expiry is None:
        return None
    if isinstance(raw_expiry, datetime):
        return raw_expiry
    if hasattr(raw_expiry, "to_datetime"):
        try:
            return raw_expiry.to_datetime()
        except Exception:
            pass
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


def _is_subscription_active(user: dict) -> tuple[bool, str, datetime | None]:
    plan = _normalize_plan(user.get("plan"))
    expiry = _parse_expiry(user.get("expiry"))
    premium_flag = user.get("isPremium") is True or user.get("premium") is True
    if plan == "FREE":
        return False, plan, expiry
    if expiry is not None and datetime.utcnow() >= expiry.replace(tzinfo=None):
        return False, plan, expiry
    if premium_flag or expiry is not None:
        return True, plan, expiry
    return False, plan, expiry

# -----------------------------
# FIRESTORE HELPERS
# -----------------------------
def user_ref(user_id: str):
    db = get_db()
    if db is None:
        raise HTTPException(status_code=503, detail="DATABASE_UNAVAILABLE")
    return db.collection("subscriptions").document(user_id)

def get_user(user_id: str):
    ref = user_ref(user_id)
    snap = ref.get()

    if not snap.exists:
        data = {
            "plan": "FREE",
            "chat_used": 0,
            "mistake_used": 0,
            "compare_used": 0,
            "expiry": None,
            "updated_at": datetime.utcnow().isoformat(),
        }
        ref.set(data)
        return data

    return snap.to_dict()

def save_user(user_id: str, data: dict):
    data["updated_at"] = datetime.utcnow().isoformat()
    user_ref(user_id).set(data)

# -----------------------------
# SUBSCRIPTION STATUS
# -----------------------------
@router.get("/subscription")
def subscription_status(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    user_id = None
    if credentials and credentials.credentials:
        try:
            user_id = verify_firebase_token(credentials.credentials)
        except Exception:
            raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    user = get_user(user_id)
    active, normalized_plan, expiry = _is_subscription_active(user)

    if not active and normalized_plan != "FREE" and expiry is not None:
        user["plan"] = "FREE"
        user["expiry"] = None
        save_user(user_id, user)
        normalized_plan = "FREE"

    plan_cfg = PLANS.get(normalized_plan, PLANS["FREE"])

    return {
        "premium": active,
        "plan": normalized_plan,
        "limits": {
            "chat": plan_cfg["chat_limit"],
            "mistake": plan_cfg["mistake_limit"],
            "compare": plan_cfg["compare_limit"],
        },
        "used": {
            "chat": user["chat_used"],
            "mistake": user["mistake_used"],
            "compare": user["compare_used"],
        },
        "expiry": expiry.isoformat() if expiry is not None else None,
    }

# -----------------------------
# ACTIVATE PLAN (after payment)
# -----------------------------
@router.post("/subscription/activate")
def activate_plan(
    request: Request,
    payload: ActivatePlanRequest,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    user_id = None
    if credentials and credentials.credentials:
        try:
            user_id = verify_firebase_token(credentials.credentials)
        except Exception:
            raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    plan = payload.plan.strip().lower()

    if plan in PLAN_ALIASES:
        plan = PLAN_ALIASES[plan]

    if plan not in PLANS:
        raise HTTPException(status_code=400, detail="Invalid plan")

    duration = PLANS[plan]["duration_days"]

    data = {
        "plan": plan,
        "chat_used": 0,
        "mistake_used": 0,
        "compare_used": 0,
        "expiry": (datetime.utcnow() + timedelta(days=duration)).isoformat() if duration > 0 else None,
    }

    save_user(user_id, data)
    return {"status": "activated", "plan": plan}

# -----------------------------
# USAGE ENDPOINTS
# -----------------------------
def _check_access(user_id: str, key: str):
    user = get_user(user_id)
    active, normalized_plan, expiry = _is_subscription_active(user)

    if normalized_plan == "FREE" or not active:
        if normalized_plan != "FREE" and expiry is not None:
            user["plan"] = "FREE"
            user["expiry"] = None
            save_user(user_id, user)
            raise HTTPException(status_code=403, detail="PLAN_EXPIRED")
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")

    limit = PLANS[normalized_plan][key + "_limit"]
    used_key = key + "_used"

    if user[used_key] >= limit:
        raise HTTPException(status_code=403, detail=f"{key.upper()}_LIMIT_REACHED")

    user[used_key] += 1
    save_user(user_id, user)

    return {"remaining": limit - user[used_key]}

@router.post("/use/chat")
def use_chat(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    user_id = None
    if credentials and credentials.credentials:
        try:
            user_id = verify_firebase_token(credentials.credentials)
        except Exception:
            raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")
    return _check_access(user_id, "chat")


@router.post("/use/mistake")
def use_mistake(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    user_id = None
    if credentials and credentials.credentials:
        try:
            user_id = verify_firebase_token(credentials.credentials)
        except Exception:
            raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")
    return _check_access(user_id, "mistake")


@router.post("/use/compare")
def use_compare(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    user_id = None
    if credentials and credentials.credentials:
        try:
            user_id = verify_firebase_token(credentials.credentials)
        except Exception:
            raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")
    return _check_access(user_id, "compare")
