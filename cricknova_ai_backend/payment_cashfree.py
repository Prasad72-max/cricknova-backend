from fastapi import APIRouter, Body, Request
import requests
import os
from dotenv import load_dotenv
from cricknova_ai_backend.subscriptions_store import create_or_update_subscription
from cricknova_ai_backend.auth import get_current_user

load_dotenv()

router = APIRouter(prefix="/payment", tags=["Cashfree Payment"])

CASHFREE_APP_ID = os.getenv("CASHFREE_APP_ID")
CASHFREE_SECRET_KEY = os.getenv("CASHFREE_SECRET_KEY")
print("CASHFREE_APP_ID =", CASHFREE_APP_ID)
print("CASHFREE_SECRET_KEY =", "SET" if CASHFREE_SECRET_KEY else None)

# Use SANDBOX for now
CASHFREE_BASE_URL = "https://sandbox.cashfree.com/pg"


@router.post("/create-order")
def create_cashfree_order(data: dict = Body(...)):
    """
    Expected data from app:
    {
        "order_amount": 99,
        "order_currency": "INR",
        "customer_id": "user_123",
        "customer_email": "test@email.com",
        "customer_phone": "9999999999"
    }
    """

    headers = {
        "Content-Type": "application/json",
        "X-Client-Id": CASHFREE_APP_ID,
        "X-Client-Secret": CASHFREE_SECRET_KEY,
        "X-Api-Version": "2023-08-01"
    }

    payload = {
        "order_id": f"cricknova_{data['customer_id']}_{int(__import__('time').time())}",
        "order_amount": data["order_amount"],
        "order_currency": data.get("order_currency", "INR"),
        "customer_details": {
            "customer_id": data["customer_id"],
            "customer_email": data["customer_email"],
            "customer_phone": data["customer_phone"]
        },
        "order_meta": {
            "return_url": "https://cricknova.app/payment-success",
            "notify_url": "https://cricknova.app/webhook/cashfree"
        },
        "order_note": "CrickNova Premium Subscription"
    }

    response = requests.post(
        f"{CASHFREE_BASE_URL}/orders",
        headers=headers,
        json=payload,
        timeout=15
    )

    if response.status_code != 200:
        return {
            "status": "failed",
            "error": response.text
        }

    result = response.json()

    return {
        "status": "success",
        "order_id": result["order_id"],
        "payment_session_id": result["payment_session_id"]
    }


# Payment verification endpoint
@router.post("/verify-payment")
def verify_cashfree_payment(data: dict = Body(...), request: Request = None):
    """
    Expected data from app:
    {
        "order_id": "cricknova_user_123_1690000000"
    }
    """

    headers = {
        "Content-Type": "application/json",
        "X-Client-Id": CASHFREE_APP_ID,
        "X-Client-Secret": CASHFREE_SECRET_KEY,
        "X-Api-Version": "2023-08-01"
    }

    order_id = data.get("order_id")
    plan_raw = data.get("plan", "monthly")

    auth_header = request.headers.get("Authorization") if request else None
    user_id = get_current_user(authorization=auth_header)

    if not order_id or not user_id:
        return {"status": "failed", "reason": "USER_NOT_AUTHENTICATED"}

    # Normalize plan
    plan_map = {
        "monthly": "IN_99",
        "99": "IN_99",
        "INR_99": "IN_99",
        "yearly": "IN_599",
        "599": "IN_599",
        "INR_599": "IN_599"
    }
    plan = plan_map.get(str(plan_raw), "IN_99")

    response = requests.get(
        f"{CASHFREE_BASE_URL}/orders/{order_id}",
        headers=headers,
        timeout=15
    )

    if response.status_code != 200:
        return {
            "status": "failed",
            "error": response.text
        }

    result = response.json()

    if result.get("order_status") == "PAID":
        create_or_update_subscription(
            user_id=user_id,
            plan=plan,
            provider="cashfree",
            order_id=order_id
        )

        return {
            "status": "success",
            "success": True,
            "verified": True,
            "premium": True,
            "premium_activated": True,
            "order_id": order_id,
            "payment_status": "PAID",
            "plan": plan,
            "user_id": user_id
        }

    return {
        "status": "pending",
        "success": False,
        "verified": False,
        "premium_activated": False,
        "order_status": result.get("order_status")
    }