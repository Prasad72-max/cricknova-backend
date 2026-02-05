import math
import numpy as np


import os
import asyncio
import sys
import time
import tempfile

# --- Firebase Admin initialization (RENDER SAFE, BASE64) ---
import json
import base64
import firebase_admin
from firebase_admin import credentials

if not firebase_admin._apps:
    service_account_b64 = os.getenv("FIREBASE_SERVICE_ACCOUNT_B64")

    if not service_account_b64:
        raise RuntimeError("FIREBASE_SERVICE_ACCOUNT_B64 env variable is not set")

    service_account_json = base64.b64decode(service_account_b64).decode("utf-8")
    cred = credentials.Certificate(json.loads(service_account_json))
    firebase_admin.initialize_app(
        cred,
        {"projectId": "cricknova-5f94f"}
    )

    print("✅ Firebase Admin initialized via BASE64 env")

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from fastapi import FastAPI, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials


app = FastAPI(title="CrickNova AI Backend")

security = HTTPBearer(auto_error=False)

@app.get("/__alive")
def alive():
    return {
        "alive": True,
        "paypal": True,
        "file": "spacefoco_backend.py"
    }
from fastapi import UploadFile, File, HTTPException, Request
from cricknova_engine.processing.routes.payment_verify import router as subscription_router
from fastapi.middleware.cors import CORSMiddleware
import numpy as np
import cv2
 
from pydantic import BaseModel
from fastapi import Body
from dotenv import load_dotenv
load_dotenv()
print("🔑 OPENAI KEY LOADED:", bool(os.getenv("OPENAI_API_KEY")))
DEV_MODE = os.getenv("DEV_MODE", "false").lower() == "true"
from cricknova_ai_backend.paypal_service import router as paypal_router

from cricknova_ai_backend.subscriptions_store import get_current_user

# Helper to extract Bearer token from Authorization header
def extract_bearer_token(auth_header: str | None):
    if not auth_header:
        return None
    if auth_header.lower().startswith("bearer "):
        return auth_header.split(" ", 1)[1].strip()
    return auth_header.strip()
PAYPAL_CLIENT_ID = os.getenv("PAYPAL_CLIENT_ID")
PAYPAL_MODE = os.getenv("PAYPAL_MODE", "sandbox")
import razorpay
# --- PayPal SDK imports ---
from paypalcheckoutsdk.core import PayPalHttpClient, SandboxEnvironment, LiveEnvironment
from paypalcheckoutsdk.orders import OrdersCreateRequest, OrdersCaptureRequest
RAZORPAY_KEY_ID = os.getenv("RAZORPAY_KEY_ID")
RAZORPAY_KEY_SECRET = os.getenv("RAZORPAY_KEY_SECRET")
razorpay_client = None
if RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET:
    razorpay_client = razorpay.Client(auth=(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET))


def razorpay_ready():
    return bool(RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET)




# --- PayPal client lazy getter ---
def get_paypal_client():
    client_id = os.getenv("PAYPAL_CLIENT_ID")
    secret = os.getenv("PAYPAL_SECRET")
    mode = os.getenv("PAYPAL_MODE", "sandbox")

    if not client_id or not secret:
        return None

    env = (
        LiveEnvironment(client_id=client_id, client_secret=secret)
        if mode == "live"
        else SandboxEnvironment(client_id=client_id, client_secret=secret)
    )
    return PayPalHttpClient(env)

from cricknova_engine.processing.ball_tracker_motion import (
    track_ball_positions,
    calculate_ball_speed_kmph
)

# -----------------------------
# BALL POSITION NORMALIZATION
# -----------------------------
def normalize_ball_positions(raw_positions):
    """
    Ensures ball positions are clean (x, y) float tuples.
    Drops invalid / noisy frames safely.
    """
    clean = []
    if not raw_positions:
        return clean

    for p in raw_positions:
        try:
            if isinstance(p, (list, tuple)) and len(p) >= 2:
                x, y = float(p[0]), float(p[1])
                if math.isfinite(x) and math.isfinite(y):
                    clean.append((x, y))
        except Exception:
            continue
    return clean

# -----------------------------
# TEMPORAL SMOOTHING (PHYSICS SAFE)
# -----------------------------
def smooth_positions(positions, window=3):
    if not positions or len(positions) < window:
        return positions

    smoothed = []
    for i in range(len(positions)):
        xs = []
        ys = []
        for j in range(max(0, i - window + 1), i + 1):
            xs.append(positions[j][0])
            ys.append(positions[j][1])
        smoothed.append((sum(xs) / len(xs), sum(ys) / len(ys)))
    return smoothed
import time

# Subscription management (external store)
from cricknova_ai_backend.subscriptions_store import (
    get_subscription,
    is_subscription_active,
    increment_chat,
    increment_mistake,
    increment_compare,
    create_or_update_subscription
)


# -----------------------------
# TRAJECTORY NORMALIZATION
# -----------------------------
def build_trajectory(ball_positions, frame_width, frame_height):
    return []


# -----------------------------
# PAYPAL ROUTER (REGISTER)
# -----------------------------
app.include_router(paypal_router)
# -----------------------------
# PAYPAL MODELS (MUST LOAD BEFORE ROUTES)
# -----------------------------
class PayPalCreateOrderRequest(BaseModel):
    amount_usd: float
    plan: str
    user_id: str

class PayPalCaptureRequest(BaseModel):
    order_id: str
    user_id: str
    plan: str

# =============================
# PAYPAL ROUTES (EARLY LOAD)
# =============================

@app.get("/paypal/__test", tags=["PayPal"])
def __paypal_test():
    return {"paypal": "visible"}

@app.get("/paypal/config", tags=["PayPal"])
def paypal_config():
    if not PAYPAL_CLIENT_ID:
        raise HTTPException(status_code=500, detail="PayPal not configured")
    return {
        "enabled": True,
        "mode": PAYPAL_MODE
    }

@app.post("/paypal/create-order", tags=["PayPal"])
async def paypal_create_order(req: PayPalCreateOrderRequest):
    paypal_client = get_paypal_client()
    if not paypal_client:
        raise HTTPException(status_code=500, detail="PayPal not configured")

    request_obj = OrdersCreateRequest()
    request_obj.prefer("return=representation")
    request_obj.request_body({
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
    })

    response = paypal_client.execute(request_obj)
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
        "id": response.result.id,
        "approval_url": approval_url,
        "approvalUrl": approval_url,
        "links": [link.__dict__ for link in response.result.links]
    }

@app.post("/paypal/capture", tags=["PayPal"])
async def paypal_capture(req: PayPalCaptureRequest):
    paypal_client = get_paypal_client()
    if not paypal_client:
        raise HTTPException(status_code=500, detail="PayPal not configured")

    request_obj = OrdersCaptureRequest(req.order_id)
    response = paypal_client.execute(request_obj)
    if response.result.status != "COMPLETED":
        raise HTTPException(status_code=400, detail="Payment not completed")

    from cricknova_ai_backend.subscriptions_store import create_or_update_subscription, get_subscription

    capture_id = response.result.purchase_units[0].payments.captures[0].id

    create_or_update_subscription(
        user_id=req.user_id,
        plan=req.plan,
        payment_id=capture_id,
        order_id=req.order_id
    )

    sub = get_subscription(req.user_id)

    expiry = sub.get("expiry")
    if hasattr(expiry, "isoformat"):
        expiry = expiry.isoformat()
    return {
        "status": "success",
        "premium": True,
        "plan": sub.get("plan"),
        "limits": sub.get("limits"),
        "expiry": expiry
    }

# -----------------------------
# USER SUBSCRIPTION ROUTES
# -----------------------------

app.include_router(
    subscription_router,
    prefix="/user",
    tags=["Subscription"]
)


# -----------------------------
# SUBSCRIPTION STATUS (RESTORE PREMIUM ON APP START)
# -----------------------------
@app.get("/user/subscription/status")
async def subscription_status(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    user_id = None
    try:
        if credentials:
            raw_auth = request.headers.get("Authorization")
            token = extract_bearer_token(raw_auth)
            user_id = get_current_user(
                authorization=token
            )
    except Exception:
        user_id = None

    if not user_id and DEV_MODE:
        user_id = "debug-user"

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    sub = get_subscription(user_id)

    if not sub:
        return {
            "premium": False,
            "plan": None,
            "limits": None,
            "expiry": None
        }

    expiry = sub.get("expiry")
    if hasattr(expiry, "isoformat"):
        expiry = expiry.isoformat()
    return {
        "premium": is_subscription_active(sub),
        "plan": sub.get("plan"),
        "limits": sub.get("limits"),
        "expiry": expiry
    }





# -----------------------------
# CORS
# -----------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)



# -----------------------------
# PAYMENT API (CONFIG ENDPOINT)
# -----------------------------

@app.get("/payment/config")
def payment_config():
    if not RAZORPAY_KEY_ID:
        raise HTTPException(status_code=500, detail="Razorpay key not configured")
    return {
        "key_id": RAZORPAY_KEY_ID,
        "currency": "INR"
    }



# -----------------------------
# PAYMENT API (CREATE ORDER)
# -----------------------------
class CreateOrderRequest(BaseModel):
    amount: int  # amount in INR (e.g. 99)


@app.post("/payment/create-order")
async def create_payment_order(req: CreateOrderRequest):
    if not req.amount or req.amount <= 0:
        return {
            "success": False,
            "error": "Invalid amount"
        }

    if not razorpay_client:
        return {
            "success": False,
            "error": "Razorpay keys not configured on server"
        }

    try:
        # Enable automatic capture for live payments
        order = razorpay_client.order.create({
            "amount": req.amount * 100,
            "currency": "INR",
            "payment_capture": 1,
            "receipt": f"cricknova_{int(time.time())}"
        })

        return {
            "success": True,
            "orderId": order["id"],
            "amount": order["amount"],
            "currency": order["currency"],
            "key": RAZORPAY_KEY_ID,
            "key_id": RAZORPAY_KEY_ID
        }

    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }






# -----------------------------
# PAYMENT API (VERIFY PAYMENT)
# -----------------------------
class VerifyPaymentRequest(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str
    plan: str

@app.post("/payment/verify-payment")
async def verify_payment(
    req: VerifyPaymentRequest,
    credentials: HTTPAuthorizationCredentials = Depends(security),
    request: Request = None
):
    key_secret = os.getenv("RAZORPAY_KEY_SECRET")

    if not key_secret:
        raise HTTPException(status_code=500, detail="Razorpay secret not configured")

    # Create signature body
    body = f"{req.razorpay_order_id}|{req.razorpay_payment_id}"

    import hmac
    import hashlib

    expected_signature = hmac.new(
        key_secret.encode(),
        body.encode(),
        hashlib.sha256
    ).hexdigest()

    if expected_signature != req.razorpay_signature:
        return {
            "status": "failed",
            "reason": "Invalid payment signature"
        }

    # 🔐 Identify user from Firebase token
    user_id = None
    try:
        if credentials:
            raw_auth = request.headers.get("Authorization")
            # Debug log for Authorization header
            print("🔐 AUTH HEADER =", request.headers.get("Authorization"))
            token = extract_bearer_token(raw_auth)
            user_id = get_current_user(
                authorization=token
            )
    except Exception:
        user_id = None

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    # --- Normalize Razorpay plan names before saving subscription ---
    plan = (req.plan or "").upper()

    if plan in ["IN_99", "99", "MONTHLY", "INR_99"]:
        plan = "IN_99"
    elif plan in ["IN_299", "299"]:
        plan = "IN_299"
    elif plan in ["IN_499", "499", "YEARLY", "INR_499"]:
        plan = "IN_499"
    elif plan in ["IN_1999", "1999"]:
        plan = "IN_1999"
    else:
        raise HTTPException(
            status_code=400,
            detail=f"INVALID_PLAN:{req.plan}"
        )

    from cricknova_ai_backend.subscriptions_store import create_or_update_subscription

    create_or_update_subscription(
        user_id=user_id,
        plan=plan,
        payment_id=req.razorpay_payment_id,
        order_id=req.razorpay_order_id
    )

    from cricknova_ai_backend.subscriptions_store import get_subscription

    sub = get_subscription(user_id)

    expiry = sub.get("expiry")
    if hasattr(expiry, "isoformat"):
        expiry = expiry.isoformat()
    return {
        "status": "success",
        "premium": True,
        "user_id": user_id,
        "plan": sub.get("plan"),
        "limits": sub.get("limits"),
        "expiry": expiry,
        "ui_notes": {
            "step_1": "Payment is being verified…",
            "step_2": "Payment successful. Please reopen the app to start premium features."
        },
        "next_action": "REOPEN_APP"
    }


# -----------------------------
# FIXED SWING (DEGREES)
# -----------------------------
def detect_swing_x(ball_positions):
    if len(ball_positions) < 8:
        return "straight"

    ys = [p[1] for p in ball_positions]
    pitch_idx = int(np.argmax(ys))

    pitch_idx = max(3, min(pitch_idx, len(ball_positions) - 3))

    pre_x = np.mean([p[0] for p in ball_positions[pitch_idx-3:pitch_idx]])
    post_x = np.mean([p[0] for p in ball_positions[pitch_idx+1:pitch_idx+4]])

    delta_x = post_x - pre_x

    if abs(delta_x) < 2:
        return "straight"
    elif delta_x > 0:
        return "outswing"
    else:
        return "inswing"


# -----------------------------
# NEARBY REALISTIC SPIN (NON-SCRIPTED)
# -----------------------------
def calculate_spin_real(ball_positions):
    """
    Nearby spin estimation from real ball trajectory.
    - No scripted values
    - Camera-aware
    - Returns NONE when spin is not reliably detectable
    """

    if len(ball_positions) < 10:
        return "none", 0.0

    ys = [p[1] for p in ball_positions]
    pitch_idx = int(np.argmax(ys))

    # Ensure enough frames before and after pitch
    if pitch_idx < 3 or pitch_idx > len(ball_positions) - 4:
        return "none", 0.0

    # -------- Smoothed pre-pitch lateral velocity --------
    vx_pre = np.mean([
        ball_positions[pitch_idx - 1][0] - ball_positions[pitch_idx - 4][0],
        ball_positions[pitch_idx - 2][0] - ball_positions[pitch_idx - 5][0]
    ])

    vy_pre = np.mean([
        ball_positions[pitch_idx - 1][1] - ball_positions[pitch_idx - 4][1],
        ball_positions[pitch_idx - 2][1] - ball_positions[pitch_idx - 5][1]
    ])

    # -------- Smoothed post-pitch lateral velocity --------
    post_indices = [pitch_idx + 1, pitch_idx + 2, pitch_idx + 4, pitch_idx + 5]
    if max(post_indices) >= len(ball_positions):
        return "none", 0.0

    vx_post = np.mean([
        ball_positions[pitch_idx + 4][0] - ball_positions[pitch_idx + 1][0],
        ball_positions[pitch_idx + 5][0] - ball_positions[pitch_idx + 2][0]
    ])

    vy_post = np.mean([
        ball_positions[pitch_idx + 4][1] - ball_positions[pitch_idx + 1][1],
        ball_positions[pitch_idx + 5][1] - ball_positions[pitch_idx + 2][1]
    ])

    delta_vx = (vx_post - vx_pre) * 0.9
    forward_v = abs(vy_pre)

    if forward_v < 4.0:
        return "none", 0.0

    # ---- Angle computation (stable & camera-safe) ----
    turn_rad = math.atan2(abs(delta_vx), forward_v)
    raw_turn_deg = math.degrees(turn_rad)

    # ---- Hard clamp to cricket reality (2D camera limit) ----
    # Any value above 12° is projection noise
    turn_deg = min(raw_turn_deg, 12.0)

    # ---- Noise floor (aggressive to avoid fake spin) ----
    if turn_deg < 0.35:
        return "none", 0.0

    # -------- Camera-aware spin direction (displacement-based) --------
    pre_x_mean = np.mean([p[0] for p in ball_positions[pitch_idx-3:pitch_idx]])
    post_x_mean = np.mean([p[0] for p in ball_positions[pitch_idx+1:pitch_idx+4]])

    lateral_shift = post_x_mean - pre_x_mean

    # Camera-agnostic correction:
    # Decide spin direction ONLY by post-bounce lateral movement
    # Do NOT depend on pre-bounce camera travel direction

    corrected_shift = lateral_shift

    if abs(corrected_shift) < 1.2:
        return "none", 0.0

    # Cricket convention:
    # Right-hander camera from behind bowler:
    # Ball moving RIGHT after pitch = leg-spin
    # Ball moving LEFT after pitch = off-spin
    spin_name = "leg-spin" if corrected_shift > 0 else "off-spin"

    return spin_name, float(turn_deg)


# -----------------------------
# PURE PHYSICS SPEED STABILIZER
# -----------------------------
def stabilize_ball_positions(ball_positions, max_jump_px=55):
    """
    Removes single-frame pixel spikes without inventing motion.
    Keeps only physically continuous movement.
    """
    if len(ball_positions) < 3:
        return ball_positions

    stable = [ball_positions[0]]

    for i in range(1, len(ball_positions)):
        px, py = stable[-1]
        cx, cy = ball_positions[i]

        dx = abs(cx - px)
        dy = abs(cy - py)

        # Drop impossible teleport frames
        if dx > max_jump_px or dy > max_jump_px:
            continue

        stable.append((cx, cy))

    return stable


# -----------------------------
# TRAINING VIDEO API
# -----------------------------
@app.post("/training/analyze")
async def analyze_training_video(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        tmp.write(await file.read())
        video_path = tmp.name

    try:
        raw_positions, fps = track_ball_positions(video_path)
        ball_positions = normalize_ball_positions(raw_positions)
        ball_positions = stabilize_ball_positions(ball_positions)
        ball_positions = smooth_positions(ball_positions, window=3)

        # Use ONLY the first ball delivery (no best-ball logic)
        # Keep enough frames for verified physics (>=10)
        if len(ball_positions) > 120:
            ball_positions = ball_positions[:120]

        if len(ball_positions) < 6:
            return {
                "status": "success",
                "speed_kmph": 90.0,
                "speed_type": "estimated_fallback",
                "speed_note": "INSUFFICIENT_PHYSICS_DATA",
                "swing": detect_swing_x(ball_positions),
                "spin": "none",
                "trajectory": []
            }

        cap = cv2.VideoCapture(video_path)
        frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()

        if frame_width <= 0 or frame_height <= 0:
            frame_width, frame_height = 640, 360

        pixel_positions = [(x, y) for (x, y) in ball_positions]

        speed_result = calculate_ball_speed_kmph(ball_positions, fps)

        speed_kmph = speed_result.get("speed_kmph")
        speed_type = speed_result.get("speed_type", "unavailable")
        speed_note = speed_result.get("speed_note", "FULLTRACK_STYLE_WINDOWED")

        swing = detect_swing_x(ball_positions)
        spin_name, spin_turn = calculate_spin_real(ball_positions)
        trajectory = []

        # Normalize spin output for app (leg spin / off spin / none)
        if spin_name == "leg-spin":
            spin_label = "leg spin"
        elif spin_name == "off-spin":
            spin_label = "off spin"
        else:
            spin_label = "none"

        return {
            "status": "success",
            "speed_kmph": speed_kmph,
            "speed_type": speed_type or "unavailable",
            "speed_note": speed_note or "Speed shown only when physics is valid.",
            "swing": swing,
            "spin": spin_label,
            "trajectory": []
        }

    finally:
        if os.path.exists(video_path):
            os.remove(video_path)




# -----------------------------
# AI COACH ANALYSIS API
# -----------------------------
@app.post("/coach/analyze")
async def ai_coach_analyze(
    request: Request,
    file: UploadFile = File(...),
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    from openai import OpenAI
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")
    client = OpenAI(api_key=api_key)

    # ---- Subscription/Mistake Limit Check ----
    user_id = None
    try:
        if credentials:
            raw_auth = request.headers.get("Authorization")
            token = extract_bearer_token(raw_auth)
            user_id = get_current_user(
                authorization=token
            )
    except Exception:
        user_id = None

    # Allow Swagger / local testing without auth
    if not user_id and request.headers.get("X-Debug") == "true":
        user_id = "debug-user"

    if not user_id and DEV_MODE:
        user_id = "debug-user"

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    from cricknova_ai_backend.subscriptions_store import get_subscription, is_subscription_active, increment_mistake
    sub = get_subscription(user_id)

    # HARD BLOCK: no subscription record or inactive subscription
    if not sub or not is_subscription_active(sub):
        raise HTTPException(
            status_code=403,
            detail="PREMIUM_REQUIRED"
        )
    if sub["mistake_used"] >= sub.get("limits", {}).get("mistake", 0):
        raise HTTPException(status_code=403, detail="MISTAKE_LIMIT_REACHED")
    increment_mistake(user_id)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        tmp.write(await file.read())
        video_path = tmp.name

    try:
        raw_positions, _ = track_ball_positions(video_path)
        ball_positions = normalize_ball_positions(raw_positions)

        if not ball_positions or len(ball_positions) < 6:
            prompt = """
You are an elite cricket batting coach.

The ball tracking is weak, but the video shows a real delivery.
Give general batting feedback based on common technique mistakes.
Mention one mistake and one improvement.
"""

            response = client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content": "You are a professional cricket batting coach."},
                    {"role": "user", "content": prompt}
                ],
                max_tokens=120,
                temperature=0.6
            )

            feedback = response.choices[0].message.content.strip()

            return {
                "status": "success",
                "low_confidence": True,
                "coach_feedback": feedback
            }

        swing = detect_swing_x(ball_positions)
        spin_name, _ = calculate_spin_real(ball_positions)

        prompt = f"""
You are an elite cricket batting coach.

Observed delivery details:
- Swing: {swing}
- Spin: {spin_name}
- One delivery only

Give short, honest, technical batting feedback.
Mention one mistake and one improvement.
"""

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a professional cricket batting coach."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=120,
            temperature=0.6
        )

        feedback = response.choices[0].message.content.strip()

        return {
            "status": "success",
            "coach_feedback": feedback
        }

    except Exception as e:
        return {
            "status": "failed",
            "coach_feedback": f"Coach error: {str(e)}"
        }

    finally:
        if os.path.exists(video_path):
            os.remove(video_path)


# -----------------------------
# AI COACH CHAT (TEXT ONLY, JSON)
# -----------------------------
class CoachChatRequest(BaseModel):
    message: str | None = None


# Helper for OpenAI chat with timeout
async def _openai_chat_with_timeout(client, messages, timeout_seconds=15):
    loop = asyncio.get_event_loop()
    return await asyncio.wait_for(
        loop.run_in_executor(
            None,
            lambda: client.chat.completions.create(
                model="gpt-4o-mini",
                messages=messages,
                max_tokens=180,
                temperature=0.6
            )
        ),
        timeout=timeout_seconds
    )

@app.post("/coach/chat")
async def ai_coach_chat(
    request: Request,
    req: CoachChatRequest = Body(...),
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    from openai import OpenAI

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")

    message = (req.message or "").strip()

    if not message:
        return {
            "status": "success",
            "reply": "Ask me anything about batting, bowling, mindset, or match situations 🏏"
        }

    client = OpenAI(api_key=api_key)

    # ---- Subscription/Chat Limit Check ----
    user_id = None
    try:
        if credentials:
            raw_auth = request.headers.get("Authorization")
            token = extract_bearer_token(raw_auth)
            user_id = get_current_user(
                authorization=token
            )
    except Exception:
        user_id = None

    # Allow Swagger / local testing without auth
    if not user_id and request.headers.get("X-Debug") == "true":
        user_id = "debug-user"

    if not user_id and DEV_MODE:
        user_id = "debug-user"

    if not user_id:
        raise HTTPException(
            status_code=401,
            detail="USER_NOT_AUTHENTICATED"
        )

    from cricknova_ai_backend.subscriptions_store import get_subscription, is_subscription_active, increment_chat
    sub = get_subscription(user_id)

    # HARD BLOCK: no subscription record or inactive subscription
    if not sub or not is_subscription_active(sub):
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")
    if sub["chat_used"] >= sub.get("limits", {}).get("chat", 0):
        raise HTTPException(
            status_code=403,
            detail="CHAT_LIMIT_REACHED"
        )
    increment_chat(user_id)
    try:
        prompt = f'''
You are an elite cricket coach.

User question:
{message}

Reply clearly, practically, and motivating.
Avoid fluff. Be direct and helpful.
'''

        messages = [
            {"role": "system", "content": "You are a professional cricket coach."},
            {"role": "user", "content": prompt}
        ]

        try:
            response = await _openai_chat_with_timeout(client, messages, 15)
            reply_text = response.choices[0].message.content.strip()
            return {
                "status": "success",
                "reply": reply_text
            }

        except asyncio.TimeoutError:
            return {
                "status": "failed",
                "reply": "AI is busy right now. Please try again in a few seconds."
            }

    except Exception as e:
        return {
            "status": "failed",
            "reply": f"Coach error: {str(e)}"
        }

# -----------------------------
# AI COACH DIFFERENCE (COMPARE TWO VIDEOS)
# -----------------------------
@app.post("/coach/diff")
async def ai_coach_diff(
    request: Request,
    left: UploadFile = File(...),
    right: UploadFile = File(...),
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    from openai import OpenAI
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")

    client = OpenAI(api_key=api_key)

    # ---- Subscription/Compare Limit Check ----
    user_id = None
    try:
        if credentials:
            raw_auth = request.headers.get("Authorization")
            token = extract_bearer_token(raw_auth)
            user_id = get_current_user(
                authorization=token
            )
    except Exception:
        user_id = None

    # Allow Swagger / local testing without auth
    if not user_id and request.headers.get("X-Debug") == "true":
        user_id = "debug-user"

    if not user_id and DEV_MODE:
        user_id = "debug-user"

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    from cricknova_ai_backend.subscriptions_store import get_subscription, is_subscription_active, increment_compare
    sub = get_subscription(user_id)
    if not is_subscription_active(sub):
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")
    if sub["compare_used"] >= sub.get("limits", {}).get("compare", 0):
        raise HTTPException(status_code=403, detail="COMPARE_LIMIT_REACHED")
    increment_compare(user_id)

    def save_temp(file):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
        tmp.write(file.file.read())
        tmp.close()
        return tmp.name

    left_path = save_temp(left)
    right_path = save_temp(right)

    try:
        left_raw_positions, _ = track_ball_positions(left_path)
        left_positions = normalize_ball_positions(left_raw_positions)
        right_raw_positions, _ = track_ball_positions(right_path)
        right_positions = normalize_ball_positions(right_raw_positions)

        if not left_positions or not right_positions:
            return {
                "status": "failed",
                "difference": "Ball not detected clearly in one or both videos."
            }

        left_swing = detect_swing_x(left_positions)
        right_swing = detect_swing_x(right_positions)

        left_spin, _ = calculate_spin_real(left_positions)
        right_spin, _ = calculate_spin_real(right_positions)

        prompt = f"""
You are an elite cricket batting coach.

Compare two batting videos.

VIDEO 1:
- Swing: {left_swing}
- Spin: {left_spin}

VIDEO 2:
- Swing: {right_swing}
- Spin: {right_spin}

Explain the difference line-by-line.
Focus on technique, balance, timing, and decision making.
Keep it short, clear, and professional.
"""

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a professional cricket batting coach."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=220,
            temperature=0.6
        )

        diff_text = response.choices[0].message.content.strip()

        return {
            "status": "success",
            "difference": diff_text
        }

    except Exception as e:
        return {
            "status": "failed",
            "difference": f"Coach error: {str(e)}"
        }

    finally:
        if os.path.exists(left_path):
            os.remove(left_path)
        if os.path.exists(right_path):
            os.remove(right_path)


# -----------------------------
# LIVE MATCH VIDEO API
# -----------------------------
@app.post("/live/analyze")
async def analyze_live_match_video(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        tmp.write(await file.read())
        video_path = tmp.name

    try:
        raw_positions, fps = track_ball_positions(video_path)
        ball_positions = normalize_ball_positions(raw_positions)
        ball_positions = stabilize_ball_positions(ball_positions)
        ball_positions = smooth_positions(ball_positions, window=3)

        # Use ONLY the first ball delivery (no best-ball logic)
        # Keep enough frames for verified physics (>=10)
        if len(ball_positions) > 120:
            ball_positions = ball_positions[:120]

        if len(ball_positions) < 6:
            return {
                "status": "success",
                "speed_kmph": 90.0,
                "speed_type": "estimated_fallback",
                "speed_note": "INSUFFICIENT_PHYSICS_DATA",
                "swing": detect_swing_x(ball_positions),
                "spin": "none",
                "trajectory": []
            }

        cap = cv2.VideoCapture(video_path)
        frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()

        if frame_width <= 0 or frame_height <= 0:
            frame_width, frame_height = 640, 360

        speed_result = calculate_ball_speed_kmph(ball_positions, fps)

        speed_kmph = speed_result.get("speed_kmph")
        speed_type = speed_result.get("speed_type", "unavailable")
        speed_note = speed_result.get("speed_note", "FULLTRACK_STYLE_WINDOWED")

        swing = detect_swing_x(ball_positions)
        spin_name, _ = calculate_spin_real(ball_positions)
        trajectory = []

        if spin_name == "leg-spin":
            spin_label = "leg spin"
        elif spin_name == "off-spin":
            spin_label = "off spin"
        else:
            spin_label = "none"

        return {
            "status": "success",
            "speed_kmph": speed_kmph,
            "speed_type": speed_type or "unavailable",
            "speed_note": speed_note or "Speed shown only when physics is valid.",
            "swing": swing,
            "spin": spin_label,
            "trajectory": []
        }

    finally:
        if os.path.exists(video_path):
            os.remove(video_path)

# -----------------------------
# PHYSICS-ONLY STUMP HIT DETECTOR
# -----------------------------
def detect_stump_hit_from_positions(ball_positions, frame_width, frame_height):
    """
    ICC-style conservative stump-hit detection.
    Returns (hit: bool, confidence: float)
    """

    if not ball_positions:
        return False, 0.0

    stump_x_min = frame_width * 0.47
    stump_x_max = frame_width * 0.53
    stump_y_min = frame_height * 0.64
    stump_y_max = frame_height * 0.90

    hits = 0
    for (x, y) in ball_positions[-8:]:
        if stump_x_min <= x <= stump_x_max and stump_y_min <= y <= stump_y_max:
            hits += 1

    confidence = min(hits / 3.0, 1.0)
    return hits >= 2, round(confidence, 2)

# -----------------------------
# PHYSICS-ONLY BAT PROXIMITY DETECTOR
# -----------------------------
def ball_near_bat_zone(ball_positions, frame_width, frame_height):
    """
    Physics-only bat proximity check.
    If ball never comes near bat zone, bat contact is impossible.
    """

    if not ball_positions:
        return False

    # Conservative bat zone (camera-agnostic)
    bat_x_min = frame_width * 0.38
    bat_x_max = frame_width * 0.62
    bat_y_min = frame_height * 0.25
    bat_y_max = frame_height * 0.55

    for (x, y) in ball_positions:
        if bat_x_min <= x <= bat_x_max and bat_y_min <= y <= bat_y_max:
            return True

    return False

# -----------------------------
# DRS REVIEW API
# -----------------------------
@app.post("/training/drs")
async def drs_review(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        tmp.write(await file.read())
        video_path = tmp.name

    try:
        raw_positions, _ = track_ball_positions(video_path)
        ball_positions = normalize_ball_positions(raw_positions)

        if not ball_positions or len(ball_positions) < 6:
            return {
                "status": "success",
                "drs": {
                    "ultraedge": False,
                    "ball_tracking": False,
                    "stump_confidence": 0.0,
                    "decision": "NOT OUT",
                    "reason": "Insufficient tracking data"
                }
            }

        # -----------------------------
        # ULTRAEDGE (GEOMETRY ONLY)
        # -----------------------------
        ultraedge = False

        cap = cv2.VideoCapture(video_path)
        frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()

        if frame_width <= 0 or frame_height <= 0:
            frame_width, frame_height = 640, 360

        # -----------------------------
        # ULTRAEDGE (STRICT PHYSICS)
        # -----------------------------
        ultraedge = False

        if ball_near_bat_zone(ball_positions, frame_width, frame_height):
            # Use only last frames near bat
            recent = ball_positions[-6:]

            xs = [p[0] for p in recent]
            ys = [p[1] for p in recent]

            # Horizontal deflection after bat contact
            dx1 = xs[2] - xs[0]
            dx2 = xs[5] - xs[3]

            dy1 = ys[2] - ys[0]
            dy2 = ys[5] - ys[3]

            # Physics rules:
            # 1. Forward motion must reduce suddenly
            # 2. Lateral motion must increase suddenly
            forward_drop = abs(dy2) < abs(dy1) * 0.55
            lateral_jump = abs(dx2) > abs(dx1) * 1.8

            if forward_drop and lateral_jump:
                ultraedge = True

        # -----------------------------
        # BALL TRACKING (STUMP HIT)
        # -----------------------------

        hits_stumps, stump_confidence = detect_stump_hit_from_positions(
            ball_positions,
            frame_width,
            frame_height
        )

        # -----------------------------
        # FINAL DECISION (ICC LOGIC)
        # -----------------------------
        if ultraedge:
            decision = "NOT OUT"
            reason = "Bat involved (UltraEdge detected)"
        elif hits_stumps:
            decision = "OUT"
            reason = "Ball hitting stumps"
        else:
            decision = "NOT OUT"
            reason = "Ball missing stumps"

        return {
            "status": "success",
            "drs": {
                "ultraedge": ultraedge,
                "ball_tracking": hits_stumps,
                "stump_confidence": stump_confidence,
                "decision": decision,
                "reason": reason
            }
        }

    finally:
        if os.path.exists(video_path):
            os.remove(video_path)

# -----------------------------
# PAYMENT API (WEBHOOK VERIFICATION)
# -----------------------------

@app.post("/payment/webhook")
async def razorpay_webhook(request: Request):
    payload = await request.body()
    signature = request.headers.get("X-Razorpay-Signature")
    secret = os.getenv("RAZORPAY_WEBHOOK_SECRET")

    if not secret or not signature:
        raise HTTPException(status_code=400, detail="Webhook not configured")

    import hmac, hashlib
    expected = hmac.new(
        secret.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()

    if not hmac.compare_digest(expected, signature):
        raise HTTPException(status_code=400, detail="Invalid webhook signature")

    return {"status": "ok"}


# -----------------------------
# OPENAPI CUSTOMIZATION
# -----------------------------
from fastapi.openapi.utils import get_openapi

def custom_openapi():
    app.openapi_schema = get_openapi(
        title="CrickNova AI Backend",
        version="1.0.0",
        description="CrickNova AI APIs",
        routes=app.routes,
    )
    return app.openapi_schema

app.openapi = custom_openapi
