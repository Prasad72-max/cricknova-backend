

from fastapi import APIRouter, HTTPException
import os
from pydantic import BaseModel

try:
    from paypalcheckoutsdk.core import PayPalHttpClient, LiveEnvironment, SandboxEnvironment
    from paypalcheckoutsdk.orders import OrdersCreateRequest, OrdersCaptureRequest
except Exception:
    PayPalHttpClient = None
    LiveEnvironment = None
    SandboxEnvironment = None
    OrdersCreateRequest = None
    OrdersCaptureRequest = None

router = APIRouter(prefix="/paypal", tags=["PayPal"])

PAYPAL_CLIENT_ID = os.getenv("PAYPAL_CLIENT_ID")
PAYPAL_SECRET = os.getenv("PAYPAL_SECRET")
PAYPAL_MODE = os.getenv("PAYPAL_MODE", "live")

def get_paypal_client():
    if not PAYPAL_CLIENT_ID or not PAYPAL_SECRET:
        return None

    if PayPalHttpClient is None:
        return None

    if PAYPAL_MODE == "live":
        env = LiveEnvironment(
            client_id=PAYPAL_CLIENT_ID,
            client_secret=PAYPAL_SECRET
        )
    else:
        env = SandboxEnvironment(
            client_id=PAYPAL_CLIENT_ID,
            client_secret=PAYPAL_SECRET
        )

    return PayPalHttpClient(env)


@router.get("/health")
def paypal_health():
    if not PAYPAL_CLIENT_ID or not PAYPAL_SECRET:
        return {"ok": False, "reason": "Missing PayPal credentials"}

    if PayPalHttpClient is None:
        return {"ok": False, "reason": "PayPal SDK not installed"}

    return {"ok": True, "mode": PAYPAL_MODE}

class PayPalCreateOrderRequest(BaseModel):
    amount_usd: float

@router.post("/create-order")
def create_order(req: PayPalCreateOrderRequest):
    client = get_paypal_client()
    if not client:
        raise HTTPException(status_code=500, detail="PayPal not configured")

    request = OrdersCreateRequest()
    request.prefer("return=representation")
    request.request_body({
        "intent": "CAPTURE",
        "purchase_units": [{
            "amount": {
                "currency_code": "USD",
                "value": f"{req.amount_usd:.2f}"
            }
        }]
    })

    response = client.execute(request)

    for link in response.result.links:
        if link.rel == "approve":
            return {
                "order_id": response.result.id,
                "approval_url": link.href
            }

    raise HTTPException(status_code=500, detail="Approval URL not found")

class PayPalCaptureRequest(BaseModel):
    order_id: str

@router.post("/capture")
def capture_order(req: PayPalCaptureRequest):
    client = get_paypal_client()
    if not client:
        raise HTTPException(status_code=500, detail="PayPal not configured")

    request = OrdersCaptureRequest(req.order_id)
    response = client.execute(request)

    if response.result.status != "COMPLETED":
        raise HTTPException(status_code=400, detail="Payment not completed")

    return {"status": "success", "order_id": req.order_id}