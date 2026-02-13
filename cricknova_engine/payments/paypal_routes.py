

from fastapi import APIRouter, HTTPException
import os
from pydantic import BaseModel

from paypalcheckoutsdk.core import PayPalHttpClient, SandboxEnvironment, LiveEnvironment
from paypalcheckoutsdk.orders import OrdersCreateRequest
from paypalcheckoutsdk.orders import OrdersCaptureRequest
from subscription_service import activate_subscription

router = APIRouter(prefix="/paypal", tags=["PayPal"])


def get_paypal_client():
    client_id = os.getenv("PAYPAL_CLIENT_ID")
    secret = os.getenv("PAYPAL_SECRET")
    mode = os.getenv("PAYPAL_MODE", "sandbox")

    if not client_id or not secret:
        return None

    if mode == "live":
        env = LiveEnvironment(client_id=client_id, client_secret=secret)
    else:
        env = SandboxEnvironment(client_id=client_id, client_secret=secret)

    return PayPalHttpClient(env)


@router.get("/__test")
def paypal_test():
    return {"paypal": "alive"}


class PayPalCreateOrder(BaseModel):
    amount_usd: float


@router.post("/create-order")
def paypal_create_order(req: PayPalCreateOrder):
    client = get_paypal_client()
    if not client:
        raise HTTPException(status_code=500, detail="PayPal not configured")

    request = OrdersCreateRequest()
    request.prefer("return=representation")
    request.request_body(
        {
            "intent": "CAPTURE",
            "purchase_units": [
                {
                    "amount": {
                        "currency_code": "USD",
                        "value": f"{req.amount_usd:.2f}",
                    }
                }
            ],
            "application_context": {
                "brand_name": "CrickNova AI",
                "user_action": "PAY_NOW",
                "return_url": "cricknova://paypal-success",
                "cancel_url": "cricknova://paypal-cancel",
            },
        }
    )

    response = client.execute(request)

    approval_url = None
    for link in response.result.links:
        if link.rel == "approve":
            approval_url = link.href
            break

    if not approval_url:
        raise HTTPException(status_code=500, detail="Approval URL not found")

    return {
        "success": True,
        "order_id": response.result.id,
        "approval_url": approval_url,
    }


# --- PayPal Capture Endpoint ---
class PayPalCaptureOrder(BaseModel):
    order_id: str
    user_id: str
    plan_code: str  # Example: YEARLY, ULTRA, MONTHLY


@router.post("/capture")
def paypal_capture_order(req: PayPalCaptureOrder):
    client = get_paypal_client()
    if not client:
        raise HTTPException(status_code=500, detail="PayPal not configured")

    capture_request = OrdersCaptureRequest(req.order_id)
    capture_request.request_body({})

    response = client.execute(capture_request)

    status = response.result.status

    if status != "COMPLETED":
        raise HTTPException(status_code=400, detail=f"Payment not completed. Status: {status}")

    # Activate subscription after successful payment
    subscription = activate_subscription(req.user_id, req.plan_code)

    return {
        "success": True,
        "status": status,
        "subscription": subscription,
    }