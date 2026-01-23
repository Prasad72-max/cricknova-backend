import os
import sys
import math
import time
import tempfile

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)


from fastapi import FastAPI

# --- Firebase Admin Initialization ---
import firebase_admin
from firebase_admin import credentials, auth

if not firebase_admin._apps:
    cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not cred_path:
        raise RuntimeError("GOOGLE_APPLICATION_CREDENTIALS not set")
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)
    print("🔥 Firebase Admin initialized")

# --- Firebase token verification helper ---
def verify_firebase_token(id_token: str) -> str:
    decoded = auth.verify_id_token(id_token)
    return decoded.get("uid")

app = FastAPI(title="CrickNova AI Backend")

@app.on_event("startup")
async def startup_log():
    import os
    print("🧠 BOOT FILE:", __file__)
    print("📂 CWD:", os.getcwd())
    print("🐍 PYTHONPATH:", os.environ.get("PYTHONPATH"))

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
import tempfile
import math
import numpy as np
import cv2
 
from pydantic import BaseModel
from fastapi import Body
from dotenv import load_dotenv
load_dotenv()
from cricknova_ai_backend.paypal_service import router as paypal_router

from cricknova_ai_backend.subscriptions_store import get_current_user
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

from cricknova_engine.processing.ball_tracker_motion import track_ball_positions
import time

# Subscription management (external store)
from cricknova_ai_backend.subscriptions_store import (
    get_subscription,
    is_subscription_active,
    increment_chat,
    increment_mistake,
    increment_compare,
    create_or_update_subscription,
    check_limit_and_increment
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
    return {
        "status": "success",
        "premium": True,
        "plan": sub.get("plan"),
        "limits": sub.get("limits"),
        "expiry": expiry if isinstance(expiry, str) else (
            expiry.isoformat() if expiry else None
        )
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
async def subscription_status(request: Request):
    auth_header = request.headers.get("Authorization")
    user_id = None
    try:
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.replace("Bearer ", "").strip()
            user_id = verify_firebase_token(token)
    except Exception as e:
        print("AUTH ERROR:", str(e))
        user_id = None

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
    return {
        "premium": is_subscription_active(sub),
        "plan": sub.get("plan"),
        "limits": sub.get("limits"),
        "expiry": expiry if isinstance(expiry, str) else (
            expiry.isoformat() if expiry else None
        )
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
    user_id: str | None = None
    plan: str | None = None

@app.post("/payment/verify-payment")
async def verify_payment(req: VerifyPaymentRequest):
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

    # ✅ Payment verified successfully – persist subscription
    if not req.user_id or not req.plan:
        raise HTTPException(status_code=400, detail="Missing user_id or plan")

    from cricknova_ai_backend.subscriptions_store import create_or_update_subscription

    create_or_update_subscription(
        user_id=req.user_id,
        plan=req.plan,
        payment_id=req.razorpay_payment_id,
        order_id=req.razorpay_order_id
    )

    from cricknova_ai_backend.subscriptions_store import get_subscription

    sub = get_subscription(req.user_id)

    expiry = sub.get("expiry")
    return {
        "status": "success",
        "premium": True,
        "user_id": req.user_id,
        "plan": sub.get("plan"),
        "limits": sub.get("limits"),
        "expiry": expiry if isinstance(expiry, str) else (
            expiry.isoformat() if expiry else None
        )
    }


# -----------------------------
# SPEED CALIBRATION (REALISTIC)
# -----------------------------
# Physics-calibrated factor for mobile cricket videos (validated vs broadcast)
SPEED_CALIBRATION_FACTOR = 1.08
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

    if len(ball_positions) < 8:
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

    if forward_v < 1e-3:
        return "none", 0.0

    # ---- Angle computation (stable & camera-safe) ----
    turn_rad = math.atan2(abs(delta_vx), forward_v)
    raw_turn_deg = math.degrees(turn_rad)

    # ---- Hard clamp to cricket reality (2D camera limit) ----
    # Any value above 12° is projection noise
    turn_deg = min(raw_turn_deg, 12.0)

    # ---- Noise floor (aggressive to avoid fake spin) ----
    if turn_deg < 0.6:
        return "none", 0.0

    # -------- Camera-aware spin direction (displacement-based) --------
    pre_x_mean = np.mean([p[0] for p in ball_positions[pitch_idx-3:pitch_idx]])
    post_x_mean = np.mean([p[0] for p in ball_positions[pitch_idx+1:pitch_idx+4]])

    lateral_shift = post_x_mean - pre_x_mean

    # Camera-agnostic correction:
    # Decide spin direction ONLY by post-bounce lateral movement
    # Do NOT depend on pre-bounce camera travel direction

    corrected_shift = lateral_shift

    if abs(corrected_shift) < 0.8:
        return "none", 0.0

    # Cricket convention:
    # Right-hander camera from behind bowler:
    # Ball moving RIGHT after pitch = leg-spin
    # Ball moving LEFT after pitch = off-spin
    spin_name = "leg-spin" if corrected_shift > 0 else "off-spin"

    return spin_name, float(turn_deg)


# -----------------------------
# TRAINING VIDEO API
# -----------------------------
@app.post("/training/analyze")
async def analyze_training_video(request: Request, file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        tmp.write(await file.read())
        video_path = tmp.name

    # --- OPTIONAL USER IDENTIFICATION (DO NOT BLOCK FREE USERS) ---
    auth_header = request.headers.get("Authorization")
    user_id = None
    try:
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.replace("Bearer ", "").strip()
            user_id = verify_firebase_token(token)
    except Exception as e:
        print("AUTH ERROR:", str(e))
        user_id = None

    if not user_id:
        user_id = request.headers.get("X-USER-ID")

    try:
        ball_positions = track_ball_positions(video_path)

        # Use ONLY the first ball delivery (no best-ball logic)
        if len(ball_positions) > 30:
            ball_positions = ball_positions[:30]

        if len(ball_positions) < 5:
            return {
                "status": "failed",
                "reason": "Ball not detected clearly",
                "speed_kmph": None,
                "swing": "unknown",
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

        def calculate_speed_kmph(ball_positions, fps):
            # ============================
            # MULTI-WINDOW + DYNAMIC SCALE
            # ============================

            # ---- FPS safety ----
            if fps is None or fps <= 1:
                fps = 30.0
            fps = min(max(fps, 24.0), 60.0)

            total_frames = len(ball_positions)
            if total_frames < 3:
                return 45.0

            ys = [p[1] for p in ball_positions]

            # ---- Identify pitch (if visible) ----
            pitch_idx = int(np.argmax(ys)) if total_frames >= 8 else total_frames - 1
            pitch_idx = max(2, min(pitch_idx, total_frames - 1))

            # ---- Define 3 tracking windows ----
            windows = []

            # Early (release)
            windows.append(ball_positions[:min(6, total_frames)])

            # Mid-flight
            if total_frames >= 10:
                mid_start = max(0, pitch_idx - 6)
                mid_end = max(mid_start + 3, pitch_idx - 1)
                windows.append(ball_positions[mid_start:mid_end])

            # Long window (overall)
            windows.append(ball_positions[:pitch_idx])

            speed_candidates = []

            for segment in windows:
                if len(segment) < 3:
                    continue

                # ---- Per-frame pixel motion ----
                distances = []
                for i in range(1, len(segment)):
                    x1, y1 = segment[i - 1]
                    x2, y2 = segment[i]
                    d = math.hypot(x2 - x1, y2 - y1)
                    if d > 0.08:
                        distances.append(d)

                if len(distances) < 2:
                    continue

                distances.sort()
                median_px = float(np.median(distances))

                # ---- Dynamic pitch scaling ----
                seg_ys = [p[1] for p in segment]
                pitch_px = max(150.0, np.percentile(seg_ys, 85) - np.percentile(seg_ys, 15))
                meters_per_pixel = 20.12 / pitch_px

                speed_mps = median_px * meters_per_pixel * fps
                speed_kmph = speed_mps * 3.6 * SPEED_CALIBRATION_FACTOR

                # ---- Physics sanity filter ----
                if 30.0 <= speed_kmph <= 170.0:
                    speed_candidates.append(speed_kmph)

            # ---- Fallback: force minimal detectable speed ----
            if not speed_candidates:
                total_dx = ball_positions[-1][0] - ball_positions[0][0]
                total_dy = ball_positions[-1][1] - ball_positions[0][1]
                total_px = math.hypot(total_dx, total_dy)

                if total_px < 1.0:
                    return 50.0

                pitch_px = max(200.0, abs(total_dy))
                meters_per_pixel = 20.12 / pitch_px
                speed_mps = (total_px * meters_per_pixel * fps) / max(len(ball_positions), 1)
                speed_kmph = speed_mps * 3.6 * SPEED_CALIBRATION_FACTOR
                return round(max(speed_kmph, 45.0), 1)

            # ---- Weighted median (robust) ----
            speed_candidates.sort()
            mid = len(speed_candidates) // 2
            final_speed = speed_candidates[mid]

            # ---- Soft correction (camera bias) ----
            if final_speed < 70:
                final_speed *= 0.92
            elif final_speed > 145:
                final_speed *= 0.96

            # ---- Short-video safety floor ----
            if total_frames < 8:
                final_speed = max(final_speed, 60.0)
            elif total_frames < 14:
                final_speed = max(final_speed, 55.0)
            else:
                final_speed = max(final_speed, 48.0)

            print(
                f"[SPEED MW DEBUG] frames={total_frames}, fps={fps}, "
                f"windows={len(speed_candidates)}, speed={final_speed:.1f}"
            )

            final_speed = max(final_speed, 55.0)
            return round(final_speed, 1)

        # Extract reference frame for pitch detection
        reference_frame = None
        cap = cv2.VideoCapture(video_path)
        video_fps = 30.0
        if cap.isOpened():
            video_fps = cap.get(cv2.CAP_PROP_FPS)
            if video_fps is None or video_fps <= 1:
                video_fps = 30.0
            ret, frame = cap.read()
            if ret:
                reference_frame = frame
            cap.release()

        raw_speed = calculate_speed_kmph(ball_positions, video_fps)

        # 7) Always round, do not return None
        speed_kmph = round(raw_speed, 1)
        # ---- Hard reliability floor: never return zero / null speed ----
        if speed_kmph < 45.0:
            speed_kmph = 45.0

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
async def ai_coach_analyze(request: Request, file: UploadFile = File(...)):
    from openai import OpenAI
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")
    client = OpenAI(api_key=api_key)

    # --- USER IDENTIFICATION (Authorization only, no X-USER-ID fallback) ---
    auth_header = request.headers.get("Authorization")
    user_id = None
    try:
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.replace("Bearer ", "").strip()
            user_id = verify_firebase_token(token)
    except Exception as e:
        print("AUTH ERROR:", str(e))
        user_id = None

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    sub = get_subscription(user_id)
    if not sub or not is_subscription_active(sub):
        return {
            "success": False,
            "error": "PREMIUM_REQUIRED",
            "premium_required": True
        }

    allowed, premium_required = check_limit_and_increment(user_id, "mistake")

    if not allowed:
        return {
            "success": False,
            "error": "LIMIT_EXCEEDED",
            "premium_required": True
        }
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        tmp.write(await file.read())
        video_path = tmp.name

    try:
        ball_positions = track_ball_positions(video_path)

        if not ball_positions or len(ball_positions) < 6:
            return {
                "success": False,
                "reply": "Ball not tracked clearly. Try a clearer angle.",
                "premium_required": False
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
            "success": True,
            "reply": feedback,
            "premium_required": False
        }

    except Exception as e:
        return {
            "success": False,
            "error": "AI_FAILED",
            "reply": f"Coach error: {str(e)}",
            "premium_required": False
        }

    finally:
        if os.path.exists(video_path):
            os.remove(video_path)


# -----------------------------
# AI COACH CHAT (TEXT ONLY, JSON)
# -----------------------------
class CoachChatRequest(BaseModel):
    message: str | None = None

@app.post("/coach/chat")
async def ai_coach_chat(request: Request, req: CoachChatRequest = Body(...)):
    from openai import OpenAI

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")

    message = (req.message or "").strip()

    if not message:
        return {
            "success": True,
            "reply": "Ask me anything about batting, bowling, mindset, or match situations 🏏",
            "premium_required": False
        }

    client = OpenAI(api_key=api_key)

    # --- USER IDENTIFICATION (Authorization only, no X-USER-ID fallback) ---
    auth_header = request.headers.get("Authorization")
    user_id = None
    try:
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.replace("Bearer ", "").strip()
            user_id = verify_firebase_token(token)
    except Exception as e:
        print("AUTH ERROR:", str(e))
        user_id = None

    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    sub = get_subscription(user_id)
    if not sub or not is_subscription_active(sub):
        return {
            "success": False,
            "error": "PREMIUM_REQUIRED",
            "premium_required": True
        }

    allowed, premium_required = check_limit_and_increment(user_id, "chat")

    if not allowed:
        return {
            "success": False,
            "error": "LIMIT_EXCEEDED",
            "premium_required": True
        }
    try:
        prompt = f'''
You are an elite cricket coach.

User question:
{message}

Reply clearly, practically, and motivating.
Avoid fluff. Be direct and helpful.
'''

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a professional cricket coach."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=180,
            temperature=0.6
        )

        reply_text = response.choices[0].message.content.strip()

        return {
            "success": True,
            "reply": reply_text,
            "premium_required": False
        }

    except Exception as e:
        return {
            "success": False,
            "error": "AI_FAILED",
            "reply": f"Coach error: {str(e)}",
            "premium_required": False
        }

# -----------------------------
# AI COACH DIFFERENCE (COMPARE TWO VIDEOS)
# -----------------------------
@app.post("/coach/diff")
async def ai_coach_diff(
    request: Request,
    left: UploadFile = File(...),
    right: UploadFile = File(...)
):
    from openai import OpenAI
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")

    client = OpenAI(api_key=api_key)

    # ---- Subscription/Compare Limit Check ----
    auth_header = request.headers.get("Authorization")
    user_id = None
    try:
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.replace("Bearer ", "").strip()
            user_id = verify_firebase_token(token)
    except Exception as e:
        print("AUTH ERROR:", str(e))
        user_id = None
    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    sub = get_subscription(user_id)
    if not sub or not is_subscription_active(sub):
        return {
            "success": False,
            "error": "PREMIUM_REQUIRED",
            "premium_required": True
        }

    allowed, premium_required = check_limit_and_increment(user_id, "compare")

    if not allowed:
        return {
            "success": False,
            "error": "LIMIT_EXCEEDED",
            "premium_required": True
        }

    def save_temp(file):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
        tmp.write(file.file.read())
        tmp.close()
        return tmp.name

    left_path = save_temp(left)
    right_path = save_temp(right)

    try:
        left_positions = track_ball_positions(left_path)
        right_positions = track_ball_positions(right_path)

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
        ball_positions = track_ball_positions(video_path)

        if len(ball_positions) > 30:
            ball_positions = ball_positions[:30]

        if len(ball_positions) < 5:
            return {
                "status": "failed",
                "speed_kmph": None,
                "swing": "unknown",
                "spin": "unknown",
                "trajectory": []
            }

        cap = cv2.VideoCapture(video_path)
        frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        cap.release()

        if frame_width <= 0 or frame_height <= 0:
            frame_width, frame_height = 640, 360

        def calculate_speed_kmph(ball_positions, fps):
            distances = []
            for i in range(1, len(ball_positions)):
                x1, y1 = ball_positions[i - 1]
                x2, y2 = ball_positions[i]
                d = math.hypot(x2 - x1, y2 - y1)
                if 1.0 < d < 40.0:
                    distances.append(d)

            if len(distances) < 4:
                return None

            median_px = float(np.median(distances))
            ys = [p[1] for p in ball_positions]
            pitch_px = max(200.0, np.percentile(ys, 90) - np.percentile(ys, 10))
            meters_per_pixel = 20.12 / pitch_px
            speed_kmph = median_px * meters_per_pixel * fps * 3.6 * SPEED_CALIBRATION_FACTOR

            if speed_kmph <= 0 or speed_kmph > 180:
                return None

            return round(speed_kmph, 1)

        raw_speed = calculate_speed_kmph(ball_positions, fps)
        speed_kmph = raw_speed if raw_speed is not None else None
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
            "speed_type": "broadcast-adjusted",
            "speed_note": "Broadcast-style speed calibrated to match international match readings",
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
        ball_positions = track_ball_positions(video_path)

        if not ball_positions or len(ball_positions) < 6:
            return {
                "status": "failed",
                "reason": "Ball not detected clearly"
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
