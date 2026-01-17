from fastapi import APIRouter, Body, HTTPException
from cricknova_ai_backend.subscriptions_store import activate_plan_internal
from fastapi import Request
import razorpay
import os
from dotenv import load_dotenv

load_dotenv()

router = APIRouter(prefix="/payment", tags=["Razorpay Payment"])

RAZORPAY_KEY_ID = os.getenv("RAZORPAY_KEY_ID")
RAZORPAY_KEY_SECRET = os.getenv("RAZORPAY_KEY_SECRET")

if not RAZORPAY_KEY_ID or not RAZORPAY_KEY_SECRET:
    raise RuntimeError("Razorpay keys not set in .env")

client = razorpay.Client(
    auth=(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET)
)


# -------------------------------------------------
# CREATE ORDER (Called before opening Razorpay UI)
# -------------------------------------------------
@router.post("/create-order")
def create_order(data: dict = Body(...)):
    """
    App sends:
    {
      "amount": 99
    }
    """

    try:
        order = client.order.create({
            "amount": int(data["amount"]) * 100,  # rupees → paise
            "currency": "INR",
            "payment_capture": 1
        })

        return {
            "success": True,
            "orderId": order["id"],
            "amount": order["amount"],
            "currency": order["currency"]
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# -------------------------------------------------
# VERIFY PAYMENT (MANDATORY)
# -------------------------------------------------
@router.post("/verify-payment")
def verify_payment(request: Request, data: dict = Body(...)):
    """
    App sends after payment success:
    {
      "razorpay_order_id": "...",
      "razorpay_payment_id": "...",
      "razorpay_signature": "..."
    }
    """

    try:
        client.utility.verify_payment_signature({
            "razorpay_order_id": data["razorpay_order_id"],
            "razorpay_payment_id": data["razorpay_payment_id"],
            "razorpay_signature": data["razorpay_signature"],
        })

        user_id = request.headers.get("X-USER-ID")
        if not user_id:
            raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

        plan = data.get("plan")
        if not plan:
            raise HTTPException(status_code=400, detail="PLAN_REQUIRED")

        # 🔥 Activate subscription in backend (single source of truth)
        activate_plan_internal(
            user_id=user_id,
            plan=plan
        )

        return {
            "success": True,
            "verified": True,
            "premium_activated": True,
            "plan": plan
        }

    except razorpay.errors.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid payment signature")