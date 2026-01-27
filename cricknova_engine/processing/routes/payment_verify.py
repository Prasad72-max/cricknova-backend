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
    print("🧾 VERIFY PAYLOAD =", data.dict())
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.lower().startswith("bearer "):
        auth_header = auth_header.split(" ", 1)[1]
    print("🔐 VERIFY_PAYMENT Authorization =", auth_header)

    token = auth_header.strip() if auth_header else None
    print("🔑 TOKEN PRESENT =", bool(token))
    user_id = get_current_user(authorization=token)

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")
    if not data.plan:
        raise HTTPException(status_code=400, detail="PLAN_MISSING")

    secret = os.getenv("RAZORPAY_KEY_SECRET") or os.getenv("RAZORPAY_SECRET")
    secret = secret.strip() if secret else None
    if not secret:
        raise HTTPException(status_code=500, detail="Razorpay secret not configured")

    # --- Razorpay signature verification (robust) ---
    if not data.razorpay_signature:
        raise HTTPException(status_code=400, detail="SIGNATURE_MISSING")

    payload_1 = f"{data.razorpay_order_id}|{data.razorpay_payment_id}"
    payload_2 = f"{data.razorpay_payment_id}|{data.razorpay_order_id}"

    gen_sig_1 = hmac.new(
        secret.encode(),
        payload_1.encode(),
        hashlib.sha256
    ).hexdigest()

    gen_sig_2 = hmac.new(
        secret.encode(),
        payload_2.encode(),
        hashlib.sha256
    ).hexdigest()

    if not (
        hmac.compare_digest(gen_sig_1, data.razorpay_signature.strip()) or
        hmac.compare_digest(gen_sig_2, data.razorpay_signature.strip())
    ):
        print("❌ SIGNATURE MISMATCH")
        print("EXPECTED_1 =", gen_sig_1)
        print("EXPECTED_2 =", gen_sig_2)
        print("RECEIVED =", data.razorpay_signature)
        raise HTTPException(status_code=400, detail="Payment verification failed")

    PLAN_MAP = {
        # legacy labels
        "monthly": "IN_99",
        "6_months": "IN_299",
        "yearly": "IN_499",
        "ultra_pro": "IN_1999",

        # numeric strings
        "99": "IN_99",
        "299": "IN_299",
        "499": "IN_499",
        "1999": "IN_1999",

        # already-normalized
        "IN_99": "IN_99",
        "IN_299": "IN_299",
        "IN_499": "IN_499",
        "IN_1999": "IN_1999",
    }

    incoming_plan = data.plan.strip()
    incoming_plan_norm = incoming_plan.lower()
    mapped_plan = PLAN_MAP.get(incoming_plan) or PLAN_MAP.get(incoming_plan_norm)
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
        print(f"✅ SUBSCRIPTION ACTIVATED user={user_id} plan={mapped_plan}")
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