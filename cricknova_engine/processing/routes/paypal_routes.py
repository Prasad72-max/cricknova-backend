import os
import requests
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

router = APIRouter(prefix="/paypal", tags=["paypal"])

@router.get("/__test")
def paypal_test():
    return {"paypal": "ok"}

@router.get("/__paypal_test")
def paypal_test_alias():
    return {"paypal": "ok"}

@router.get("/health")
def paypal_health():
    return {
        "ok": True,
        "mode": PAYPAL_MODE,
        "base_url": BASE_URL
    }

PAYPAL_CLIENT_ID = os.getenv("PAYPAL_CLIENT_ID")
PAYPAL_SECRET = os.getenv("PAYPAL_SECRET")
PAYPAL_MODE = os.getenv("PAYPAL_MODE", "sandbox")

BASE_URL = (
    "https://api-m.sandbox.paypal.com"
    if PAYPAL_MODE == "sandbox"
    else "https://api-m.paypal.com"
)

# -----------------------------
# PAYPAL AUTH TOKEN
# -----------------------------
def get_paypal_token():
    if not PAYPAL_CLIENT_ID or not PAYPAL_SECRET:
        raise HTTPException(status_code=500, detail="PayPal keys not configured")

    response = requests.post(
        f"{BASE_URL}/v1/oauth2/token",
        auth=(PAYPAL_CLIENT_ID, PAYPAL_SECRET),
        data={"grant_type": "client_credentials"},
        headers={"Accept": "application/json"},
    )

    if response.status_code != 200:
        raise HTTPException(status_code=500, detail="Failed to get PayPal token")

    return response.json()["access_token"]


# -----------------------------
# CREATE ORDER
# -----------------------------
class CreatePayPalOrder(BaseModel):
    amount_usd: float
    plan: str | None = None
    user_id: str | None = None
    currency: str | None = "USD"


@router.post("/create-order")
def create_paypal_order(req: CreatePayPalOrder):
    token = get_paypal_token()

    payload = {
        "intent": "CAPTURE",
        "purchase_units": [
            {
                "amount": {
                    "currency_code": req.currency or "USD",
                    "value": f"{req.amount_usd:.2f}"
                }
            }
        ],
        "application_context": {
            "brand_name": "CrickNova AI",
            "user_action": "PAY_NOW",
            "return_url": "https://cricknova.app/paypal-success",
            "cancel_url": "https://cricknova.app/paypal-cancel"
        }
    }

    response = requests.post(
        f"{BASE_URL}/v2/checkout/orders",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json=payload,
    )

    if response.status_code not in (200, 201):
        raise HTTPException(status_code=500, detail="PayPal order creation failed")

    data = response.json()

    approval_url = None
    for link in data.get("links", []):
        if link.get("rel") == "approve":
            approval_url = link.get("href")
            break

    if not approval_url:
        raise HTTPException(status_code=500, detail="Approval URL not found")

    return {
        "order_id": data["id"],
        "id": data["id"],
        "approval_url": approval_url,
        "approvalUrl": approval_url,
        "links": data.get("links", []),
        "status": data["status"]
    }

@router.get("/create-order")
def create_paypal_order_get():
    return {
        "message": "Use POST method for this endpoint",
        "endpoint": "/paypal/create-order",
        "method_required": "POST"
    }


# -----------------------------
# CAPTURE ORDER
# -----------------------------
class CapturePayPalOrder(BaseModel):
    order_id: str
    user_id: str
    plan: str


@router.post("/capture-order")
def capture_paypal_order(req: CapturePayPalOrder):
    token = get_paypal_token()

    response = requests.post(
        f"{BASE_URL}/v2/checkout/orders/{req.order_id}/capture",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )

    if response.status_code not in (200, 201):
        raise HTTPException(status_code=500, detail="PayPal payment capture failed")

    data = response.json()

    if data.get("status") != "COMPLETED":
        raise HTTPException(status_code=400, detail="Payment not completed")

    # ✅ Activate subscription
    from cricknova_ai_backend.subscriptions_store import create_or_update_subscription, get_subscription

    create_or_update_subscription(
        user_id=req.user_id,
        plan=req.plan,
        payment_id=req.order_id,
        order_id=req.order_id,
    )

    sub = get_subscription(req.user_id)

    return {
        "status": "success",
        "paypal_status": data["status"],
        "premium": True,
        "plan": sub.get("plan"),
        "limits": sub.get("limits"),
        "expiry": sub.get("expiry").isoformat() if sub.get("expiry") else None,
    }

@router.post("/capture")
def capture_paypal_order_alias(req: CapturePayPalOrder):
    return capture_paypal_order(req)
