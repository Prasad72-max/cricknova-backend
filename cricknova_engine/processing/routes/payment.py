from dotenv import load_dotenv
load_dotenv()
import os
import razorpay
import hmac
import hashlib
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from cricknova_engine.processing.routes import user_subscription
from fastapi import Request
from firebase_admin import auth as firebase_auth

router = APIRouter()

# ---------- Razorpay Client ----------
try:
    client = razorpay.Client(
        auth=(
            os.getenv("RAZORPAY_KEY_ID"),
            os.getenv("RAZORPAY_KEY_SECRET"),
        )
    )
except Exception as e:
    raise RuntimeError(f"Razorpay init failed: {e}")


# ---------- Health Check Endpoint ----------
@router.get("/health")
def razorpay_health():
    return {
        "razorpay_key_loaded": bool(os.getenv("RAZORPAY_KEY_ID")),
        "status": "ok"
    }


# ---------- Request Model ----------
class CreateOrderRequest(BaseModel):
    amount: int  # amount in rupees, e.g. 99

class VerifyPaymentRequest(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str
    plan: str


# ---------- API ----------
@router.post("/create-order")
def create_order(payload: CreateOrderRequest):
    try:
        if payload.amount <= 0:
            raise HTTPException(status_code=400, detail="Invalid amount")

        order = client.order.create({
            "amount": payload.amount * 100,  # ₹ → paise
            "currency": "INR",
            "receipt": f"cricknova_rcpt_{payload.amount}",
            "payment_capture": 1,
            "notes": {
                "app": "CrickNova AI",
                "purpose": "Premium Subscription"
            }
        })

        return {
            "success": True,
            "orderId": order["id"],
            "amount": order["amount"],
            "currency": order["currency"],
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/verify-payment")
def verify_payment(payload: VerifyPaymentRequest, request: Request):
    try:
        # 🔐 Enforce Firebase Authentication
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Authorization header missing")

        id_token = auth_header.replace("Bearer ", "").strip()

        try:
            decoded_token = firebase_auth.verify_id_token(id_token)
            verified_user_id = decoded_token.get("uid")
        except Exception:
            raise HTTPException(status_code=401, detail="Invalid or expired token")

        if not verified_user_id:
            raise HTTPException(status_code=401, detail="User not authenticated")

        secret = os.getenv("RAZORPAY_KEY_SECRET")
        if not secret:
            raise HTTPException(status_code=500, detail="Razorpay secret missing")

        generated_signature = hmac.new(
            secret.encode(),
            f"{payload.razorpay_order_id}|{payload.razorpay_payment_id}".encode(),
            hashlib.sha256
        ).hexdigest()

        if generated_signature != payload.razorpay_signature:
            raise HTTPException(status_code=400, detail="Invalid payment signature")

        # TODO: store razorpay_payment_id in DB to prevent reuse

        # ✅ Activate premium plan in backend (single source of truth)
        # Map app plan codes to backend plan codes
        PLAN_MAP = {
            "monthly": "IN_99",
            "6_months": "IN_299",
            "yearly": "IN_499",
            "ultra_pro": "IN_1999",
        }

        backend_plan = PLAN_MAP.get(payload.plan)
        if not backend_plan:
            # Do NOT fail payment after success – log & continue
            return {
                "success": True,
                "status": "success",
                "premium": False,
                "premium_activated": False,
                "plan": payload.plan,
                "user_id": verified_user_id,
                "warning": "Unknown plan code"
            }

        try:
            user_subscription.activate_plan_internal(
                user_id=verified_user_id,
                plan=backend_plan
            )
            premium_activated = True
        except Exception as e:
            # 🔥 Critical fix: never mark payment as failed after Razorpay success
            premium_activated = False

        return {
            "success": True,
            "status": "success",
            "premium": premium_activated,
            "premium_activated": premium_activated,
            "plan": backend_plan,
            "user_id": verified_user_id
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Payment verification failed: {e}")