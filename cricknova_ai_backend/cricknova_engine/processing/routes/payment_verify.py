import hmac, hashlib, os
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from cricknova_engine.processing.routes.user_subscription import activate_plan

router = APIRouter()

class VerifyRequest(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str
    user_id: str
    plan: str

@router.post("/payment/verify-payment")
def verify_payment(data: VerifyRequest):
    if not data.user_id or not data.plan:
        raise HTTPException(status_code=400, detail="Invalid payment payload")

    secret = os.getenv("RAZORPAY_KEY_SECRET")
    if not secret:
        raise HTTPException(status_code=500, detail="Razorpay secret not configured")

    generated_signature = hmac.new(
        secret.encode(),
        f"{data.razorpay_order_id}|{data.razorpay_payment_id}".encode(),
        hashlib.sha256
    ).hexdigest()

    if generated_signature != data.razorpay_signature:
        raise HTTPException(status_code=400, detail="Payment verification failed")

    # ✅ PAYMENT IS REAL → ACTIVATE PLAN (single source of truth)
    activate_plan(data.user_id, data.plan)

    # TODO: Store razorpay_payment_id in DB to prevent replay attacks

    return {
        "success": True,
        "message": "Payment verified & premium activated",
        "premium_activated": True,
        "plan": data.plan,
        "user_id": data.user_id
    }