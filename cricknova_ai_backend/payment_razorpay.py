from fastapi import APIRouter, Body, HTTPException
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
@router.post("/verify")
def verify_payment(data: dict = Body(...)):
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

        # ✅ Payment verified — mark user premium here
        return {
            "success": True,
            "message": "Payment verified successfully",
            "premium_activated": True,
            "plan": "pro"
        }

    except razorpay.errors.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid payment signature")