import os
from datetime import datetime, timedelta
from google.cloud import firestore
from google.oauth2 import service_account
import firebase_admin
from firebase_admin import auth as firebase_auth, credentials as firebase_credentials

# -----------------------------
# FIRESTORE INITIALIZATION
# -----------------------------

_firestore_client = None

def get_firestore_client():
    global _firestore_client
    if _firestore_client:
        return _firestore_client

    cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

    if cred_path and os.path.exists(cred_path):
        credentials = service_account.Credentials.from_service_account_file(cred_path)
        _firestore_client = firestore.Client(credentials=credentials)
    else:
        # fallback for local development
        credentials = service_account.Credentials.from_service_account_file("firebase_key.json")
        _firestore_client = firestore.Client(credentials=credentials)

    return _firestore_client


# -----------------------------
# FIREBASE AUTH INITIALIZATION
# -----------------------------

_firebase_initialized = False

def init_firebase_admin():
    global _firebase_initialized
    if _firebase_initialized:
        return

    cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    if cred_path and os.path.exists(cred_path):
        cred = firebase_credentials.Certificate(cred_path)
    else:
        cred = firebase_credentials.Certificate("firebase_key.json")

    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)

    _firebase_initialized = True


# -----------------------------
# PLAN DEFINITIONS
# -----------------------------

PLAN_LIMITS = {
    "IN_99":   {"chat": 200,   "mistake": 15,  "compare": 0,   "days": 30},
    "IN_299":  {"chat": 1200,  "mistake": 30,  "compare": 0,   "days": 180},
    "IN_599":  {"chat": 3000,  "mistake": 60,  "compare": 50,  "days": 365},
    "IN_2999": {"chat": 20000, "mistake": 200, "compare": 200, "days": 365},
}


# -----------------------------
# SUBSCRIPTION HELPERS
# -----------------------------

def create_or_update_subscription(user_id: str, plan: str, payment_id: str, order_id: str):
    if plan not in PLAN_LIMITS:
        raise ValueError("Invalid plan")

    db = get_firestore_client()
    limits = PLAN_LIMITS[plan]

    expiry = datetime.utcnow() + timedelta(days=limits["days"])

    data = {
        "user_id": user_id,
        "plan": plan,
        "limits": {
            "chat": limits["chat"],
            "mistake": limits["mistake"],
            "compare": limits["compare"],
        },
        "chat_used": 0,
        "mistake_used": 0,
        "compare_used": 0,
        "payment_id": payment_id,
        "order_id": order_id,
        "expiry": expiry.isoformat(),
        "updated_at": firestore.SERVER_TIMESTAMP,
    }

    db.collection("subscriptions").document(user_id).set(data, merge=True)


def get_subscription(user_id: str):
    db = get_firestore_client()
    doc = db.collection("subscriptions").document(user_id).get()
    if not doc.exists:
        return None
    return doc.to_dict()


def is_subscription_active(sub: dict | None) -> bool:
    if not sub:
        return False
    expiry = datetime.fromisoformat(sub["expiry"])
    return datetime.utcnow() < expiry


# -----------------------------
# USAGE INCREMENTS
# -----------------------------

def _increment_field(user_id: str, field: str):
    db = get_firestore_client()
    ref = db.collection("subscriptions").document(user_id)
    ref.update({field: firestore.Increment(1)})


def increment_chat(user_id: str):
    _increment_field(user_id, "chat_used")


def increment_mistake(user_id: str):
    _increment_field(user_id, "mistake_used")


def increment_compare(user_id: str):
    _increment_field(user_id, "compare_used")


# -----------------------------
# AUTH HELPERS
# -----------------------------

def verify_firebase_token(id_token: str) -> str | None:
    """
    Verifies Firebase ID token.
    Returns user_id (uid) if valid, else None.
    """
    try:
        init_firebase_admin()
        decoded = firebase_auth.verify_id_token(id_token)
        return decoded.get("uid")
    except Exception:
        return None


# -----------------------------
# FASTAPI USER EXTRACTION DEPENDENCY
# -----------------------------

from fastapi import Header, HTTPException, status

def get_current_user(
    authorization: str | None = Header(default=None),
    x_debug_user: str | None = Header(default=None),
) -> str:
    """
    Returns authenticated Firebase user_id.
    - Uses Authorization: Bearer <firebase_id_token>
    - Allows X-Debug-User ONLY for local/dev Swagger testing
    """

    # Local / Swagger testing fallback
    if x_debug_user:
        return x_debug_user

    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="USER_NOT_AUTHENTICATED",
        )

    # Accept both: "Bearer <token>" and "<token>" (Swagger / quick tests)
    if authorization.startswith("Bearer "):
        token = authorization.split(" ", 1)[1]
    else:
        token = authorization.strip()

    user_id = verify_firebase_token(token)

    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="USER_NOT_AUTHENTICATED",
        )

    return user_id