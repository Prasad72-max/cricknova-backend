import hmac, hashlib, os
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
from cricknova_ai_backend.subscriptions_store import create_or_update_subscription
from cricknova_ai_backend.subscriptions_store import get_current_user

router = APIRouter()

class VerifyRequest(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str
    plan: str

@router.post("/payment/verify-payment")
def verify_payment(data: VerifyRequest, request: Request):
    auth_header = request.headers.get("Authorization")
    user_id = get_current_user(authorization=auth_header)

    if not user_id or not data.plan:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

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

    activation_error = None
    try:
        create_or_update_subscription(
            user_id=user_id,
            plan=mapped_plan,
            payment_id=data.razorpay_payment_id,
            order_id=data.razorpay_order_id
        )
    except Exception as e:
        # Do NOT fail payment after Razorpay success
        activation_error = str(e)

    return {
        "success": True,
        "status": "success",
        "premium": activation_error is None,
        "premium_activated": activation_error is None,
        "plan": mapped_plan,
        "user_id": user_id,
        "razorpay_payment_id": data.razorpay_payment_id
    }