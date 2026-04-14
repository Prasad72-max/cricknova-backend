import os
import requests
from dotenv import load_dotenv

from fastapi import APIRouter, HTTPException
from subscriptions_store import create_or_update_subscription

load_dotenv()

PAYPAL_CLIENT_ID = os.getenv("PAYPAL_CLIENT_ID")
PAYPAL_SECRET = os.getenv("PAYPAL_SECRET")
PAYPAL_MODE = os.getenv("PAYPAL_MODE", "sandbox")  # sandbox or live

BASE_URL = (
    "https://api-m.sandbox.paypal.com"
    if PAYPAL_MODE == "sandbox"
    else "https://api-m.paypal.com"
)

router = APIRouter(prefix="/paypal", tags=["paypal"])

# Test route for PayPal service
@router.get("/__test")
def paypal_test():
    return {"paypal": "ok"}

from pydantic import BaseModel

class PayPalCreateOrderBody(BaseModel):
    amount_usd: float
    user_id: str
    plan: str

class PayPalCaptureBody(BaseModel):
    order_id: str
    user_id: str
    plan: str


def get_access_token() -> str:
    """Get PayPal OAuth access token"""
    url = f"{BASE_URL}/v1/oauth2/token"
    response = requests.post(
        url,
        auth=(PAYPAL_CLIENT_ID, PAYPAL_SECRET),
        headers={"Accept": "application/json"},
        data={"grant_type": "client_credentials"},
        timeout=20,
    )
    response.raise_for_status()
    return response.json()["access_token"]


def create_order(amount_usd: float) -> dict:
    """Create PayPal order"""
    token = get_access_token()

    url = f"{BASE_URL}/v2/checkout/orders"
    payload = {
        "intent": "CAPTURE",
        "purchase_units": [
            {
                "amount": {
                    "currency_code": "USD",
                    "value": f"{amount_usd:.2f}",
                }
            }
        ],
        "application_context": {
            "brand_name": "CrickNova AI",
            "landing_page": "LOGIN",
            "user_action": "PAY_NOW",
            "return_url": "https://cricknova.app/paypal-success",
            "cancel_url": "https://cricknova.app/paypal-cancel"
        }
    }

    response = requests.post(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=20,
    )
    response.raise_for_status()
    data = response.json()
    print("PAYPAL CREATE ORDER RESPONSE:", data)
    approval_url = None
    for link in data.get("links", []):
        if link.get("rel") == "approve":
            approval_url = link.get("href")
            break

    if not approval_url:
        raise RuntimeError("PayPal approval URL missing in response")

    return {
        "id": data.get("id"),
        "status": data.get("status"),
        "approval_url": approval_url,
        "raw": data,
    }


def capture_order(order_id: str) -> dict:
    """Capture approved PayPal order"""
    token = get_access_token()

    url = f"{BASE_URL}/v2/checkout/orders/{order_id}/capture"
    response = requests.post(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        timeout=20,
    )
    response.raise_for_status()
    data = response.json()
    return {
        "id": data.get("id"),
        "status": data.get("status"),
        "raw": data,
    }


# FastAPI routes
@router.post("/create-order")
def create_paypal_order(body: PayPalCreateOrderBody):
    if not PAYPAL_CLIENT_ID or not PAYPAL_SECRET:
        raise HTTPException(status_code=500, detail="PayPal not configured")
    try:
        order = create_order(body.amount_usd)
        if not order.get("approval_url"):
            raise HTTPException(status_code=400, detail="Approval URL not generated")
        print("✅ PayPal approval_url:", order["approval_url"])
        return {
            "order_id": order["id"],
            "id": order["id"],
            "approval_url": order["approval_url"],
            "approvalUrl": order["approval_url"],
            "links": order.get("raw", {}).get("links", []),
            "status": order["status"],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/capture")
def capture_paypal_order(body: PayPalCaptureBody):
    if not PAYPAL_CLIENT_ID or not PAYPAL_SECRET:
        raise HTTPException(status_code=500, detail="PayPal not configured")
    try:
        result = capture_order(body.order_id)
        if result.get("status") != "COMPLETED":
            return {
                "status": "not_paid"
            }

        create_or_update_subscription(
            user_id=body.user_id,
            plan=body.plan,
            payment_id=result.get("id"),
            order_id=body.order_id,
        )
        return {
            "status": "success"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
