import hmac, hashlib, os
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

class VerifyRequest(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str
    user_id: str
    plan: str

@router.post("/payment/verify-payment")
def verify_payment(data: VerifyRequest):
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

    # ✅ PAYMENT IS REAL
    return {
        "status": "success",
        "premium": True,
        "plan": data.plan
    }