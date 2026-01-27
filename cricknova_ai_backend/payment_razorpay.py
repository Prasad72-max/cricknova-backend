from fastapi import APIRouter, Body, HTTPException
from cricknova_ai_backend.subscriptions_store import activate_plan_internal
from fastapi import Request
import razorpay
import os
from dotenv import load_dotenv
from cricknova_ai_backend.auth import resolve_user_id

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

        user_id = resolve_user_id(request)
        if not user_id:
            raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

        raw_plan = data.get("plan")

        # Fallback: infer plan from amount if plan not sent by app
        if not raw_plan:
            amount = data.get("amount")
            if amount in (99, "99", 9900, "9900"):
                raw_plan = "monthly"
            elif amount in (499, "499", 49900, "49900"):
                raw_plan = "yearly"
            else:
                raw_plan = "monthly"

        # Normalize / alias plans coming from app or Razorpay
        PLAN_ALIAS = {
            "monthly": "IN_99",
            "yearly": "IN_499",
            "INR_99": "IN_99",
            "INR_499": "IN_499",
            "99": "IN_99",
            "499": "IN_499",
        }

        plan = PLAN_ALIAS.get(raw_plan, raw_plan)

        # 🔥 Activate subscription in backend (single source of truth)
        activate_plan_internal(
            user_id=user_id,
            plan=plan
        )

        return {
            "success": True,
            "verified": True,
            "premium": True,
            "premium_activated": True,
            "plan": plan,
            "user_id": user_id
        }

    except razorpay.errors.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid payment signature")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))