from dotenv import load_dotenv
load_dotenv()
import os
import razorpay
import hmac
import hashlib
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from cricknova_engine.processing.routes.user_subscription import activate_plan

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
    user_id: str
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
def verify_payment(payload: VerifyPaymentRequest):
    try:
        if not payload.plan or not payload.user_id:
            raise HTTPException(status_code=400, detail="Invalid payment payload")

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
        activate_plan(payload.user_id, payload.plan)

        return {
            "success": True,
            "message": "Payment verified & premium activated",
            "premium_activated": True,
            "plan": payload.plan
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))