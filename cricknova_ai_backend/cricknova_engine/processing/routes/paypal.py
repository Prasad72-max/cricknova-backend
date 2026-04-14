from fastapi import APIRouter, HTTPException
import logging
from pydantic import BaseModel
import os
import requests


router = APIRouter(prefix="/paypal", tags=["PayPal"])


# Test endpoint for PayPal route
@router.get("/__test")
def paypal_test():
    return {"paypal": "ok"}

# Alias endpoint for PayPal test
@router.get("/__paypal_test")
def paypal_test_alias():
    return {"paypal": "ok"}

PAYPAL_CLIENT_ID = os.getenv("PAYPAL_CLIENT_ID")
PAYPAL_SECRET = os.getenv("PAYPAL_SECRET")
PAYPAL_MODE = os.getenv("PAYPAL_MODE", "sandbox")

logger = logging.getLogger("paypal")

BASE_URL = (
    "https://api-m.sandbox.paypal.com"
    if PAYPAL_MODE == "sandbox"
    else "https://api-m.paypal.com"
)

def get_token():
    r = requests.post(
        f"{BASE_URL}/v1/oauth2/token",
        auth=(PAYPAL_CLIENT_ID, PAYPAL_SECRET),
        data={"grant_type": "client_credentials"},
    )
    if r.status_code != 200:
        logger.error(f"PayPal auth failed: {r.text}")
        raise HTTPException(500, "PayPal auth failed")

    data = r.json()
    if "access_token" not in data:
        logger.error(f"PayPal token missing: {data}")
        raise HTTPException(500, "PayPal token missing")

    return data["access_token"]

class CreateOrder(BaseModel):
    amount_usd: float
    plan: str
    user_id: str

@router.post("/create-order")
def create_order(req: CreateOrder):
    token = get_token()
    r = requests.post(
        f"{BASE_URL}/v2/checkout/orders",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json={
            "intent": "CAPTURE",
            "purchase_units": [{
                "amount": {
                    "currency_code": "USD",
                    "value": f"{req.amount_usd:.2f}"
                }
            }],
            "application_context": {
                "brand_name": "CrickNova AI",
                "user_action": "PAY_NOW",
                "return_url": "https://cricknova.app/paypal-success",
                "cancel_url": "https://cricknova.app/paypal-cancel"
            }
        }
    )
    data = r.json()
    if "id" not in data or "links" not in data:
        logger.error(f"Invalid PayPal create order response: {data}")
        raise HTTPException(500, "Invalid PayPal response")

    approval_url = None
    for link in data["links"]:
        if link.get("rel") == "approve":
            approval_url = link.get("href")
            break

    if not approval_url:
        logger.error(f"Approval URL not found: {data}")
        raise HTTPException(500, "Approval URL not found")

    logger.info(f"PayPal order created: {data['id']}")

    return {
        "order_id": data["id"],
        "id": data["id"],
        "approval_url": approval_url,
        "approvalUrl": approval_url,
        "links": data.get("links", [])
    }

class CaptureOrder(BaseModel):
    order_id: str
    user_id: str
    plan: str

def capture_order_internal(req: CaptureOrder):
    token = get_token()
    r = requests.post(
        f"{BASE_URL}/v2/checkout/orders/{req.order_id}/capture",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )

    logger.info(f"PayPal capture response ({r.status_code}): {r.text}")

    if r.status_code not in (200, 201):
        raise HTTPException(500, "PayPal capture failed")

    data = r.json()

    if data.get("status") != "COMPLETED":
        raise HTTPException(400, "Payment not completed")

    return {
        "order_id": data["id"],
        "status": data["status"]
    }

@router.post("/capture-order")
def capture_order(req: CaptureOrder):
    return capture_order_internal(req)

@router.post("/capture")
def capture(req: CaptureOrder):
    return capture_order_internal(req)