import hmac, hashlib, os
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from cricknova_ai_backend.subscriptions_store import create_or_update_subscription

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

    secret = os.getenv("RAZORPAY_KEY_SECRET") or os.getenv("RAZORPAY_SECRET")
    secret = secret.strip()
    if not secret:
        raise HTTPException(status_code=500, detail="Razorpay secret not configured")

    generated_signature = hmac.new(
        secret.encode(),
        f"{data.razorpay_order_id}|{data.razorpay_payment_id}".encode(),
        hashlib.sha256
    ).hexdigest()

    if not hmac.compare_digest(generated_signature, data.razorpay_signature.strip()):
        raise HTTPException(status_code=400, detail="Payment verification failed")

    PLAN_MAP = {
        "monthly": "IN_99",
        "6_months": "IN_299",
        "yearly": "IN_499",
        "ultra_pro": "IN_1999",
    }

    mapped_plan = PLAN_MAP.get(data.plan)
    if not mapped_plan:
        raise HTTPException(status_code=400, detail=f"Unknown plan: {data.plan}")

    # ✅ PAYMENT IS REAL → ACTIVATE PLAN (single source of truth)
    try:
        create_or_update_subscription(
            user_id=data.user_id,
            plan=mapped_plan,
            payment_id=data.razorpay_payment_id,
            order_id=data.razorpay_order_id
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Plan activation failed: {e}")

    # TODO: Store razorpay_payment_id in DB to prevent replay attacks

    return {
        "success": True,
        "status": "success",
        "premium_activated": True,
        "backend_plan": mapped_plan,
        "app_plan": data.plan,
        "user_id": data.user_id,
        "razorpay_payment_id": data.razorpay_payment_id
    }