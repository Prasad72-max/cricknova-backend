print("111111")
import os
import sys
import math
import time
import tempfile

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)


from fastapi import FastAPI, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

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
def verify_firebase_token(token: str) -> str:
    if not token:
        raise ValueError("Missing token")

    # Token MUST already be raw JWT (no 'Bearer ')
    decoded = auth.verify_id_token(token)

    uid = decoded.get("uid")
    if not uid:
        raise ValueError("UID missing in token")

    return uid
app = FastAPI(title="CrickNova AI Backend")
security = HTTPBearer(auto_error=True)

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
    check_limit_and_increment,
    save_firestore_subscription
)


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

    # --- Firestore sync ---
    try:
        sub = get_subscription(req.user_id)
        if sub:
            save_firestore_subscription(req.user_id, sub)
    except Exception as e:
        print("FIRESTORE SAVE FAILED:", str(e))

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
async def subscription_status(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    user_id = None
    try:
        if credentials:
            user_id = verify_firebase_token(credentials.credentials)
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

    # --- Firestore sync ---
    try:
        sub = get_subscription(req.user_id)
        if sub:
            save_firestore_subscription(req.user_id, sub)
    except Exception as e:
        print("FIRESTORE SAVE FAILED:", str(e))

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
# PHYSICS CONSTANTS
# -----------------------------
CRICKET_PITCH_METERS = 20.12  # 22 yards
STUMP_WIDTH_METERS = 0.2286   # 22.86 cm
SPEED_CALIBRATION_FACTOR = 1.0  # compatibility for legacy routes


def _safe_unit(vec):
    n = float(np.linalg.norm(vec))
    if n <= 1e-9:
        return np.array([0.0, 1.0], dtype=np.float32)
    return vec / n


def _extract_track(track_output):
    if isinstance(track_output, tuple) and len(track_output) >= 2:
        return list(track_output[0]), float(track_output[1])
    return list(track_output), 30.0


def _trajectory_axes(ball_positions):
    pts = np.asarray(ball_positions, dtype=np.float32)
    if len(pts) < 2:
        return pts, np.array([0.0, 1.0], dtype=np.float32), np.array([1.0, 0.0], dtype=np.float32)
    fwd = _safe_unit(pts[-1] - pts[0])
    lat = np.array([-fwd[1], fwd[0]], dtype=np.float32)
    return pts, fwd, lat


def _progress_and_lateral(pts, origin, fwd, lat):
    rel = pts - origin
    progress = rel @ fwd
    lateral = rel @ lat
    return progress, lateral


def _release_index(progress):
    if len(progress) < 4:
        return 0
    diffs = np.diff(progress)
    noise = np.median(np.abs(diffs)) if len(diffs) else 0.0
    threshold = max(0.5, float(noise) * 0.5)
    for i in range(len(diffs) - 2):
        if diffs[i] > threshold and diffs[i + 1] > threshold and diffs[i + 2] > threshold:
            return i
    return 0


def _pitch_index(lateral):
    if len(lateral) < 6:
        return max(0, len(lateral) // 2)
    curv = []
    for i in range(1, len(lateral) - 1):
        curv.append(abs(lateral[i + 1] - 2 * lateral[i] + lateral[i - 1]))
    if not curv:
        return max(0, len(lateral) // 2)
    return int(np.argmax(curv)) + 1


def build_trajectory(ball_positions, frame_width, frame_height):
    if frame_width <= 0:
        frame_width = 640
    if frame_height <= 0:
        frame_height = 360
    trajectory = []
    for i, (x, y) in enumerate(ball_positions):
        trajectory.append({
            "x": float(x) / float(frame_width),
            "y": float(y) / float(frame_height),
            "frame": int(i),
        })
    return trajectory


def calculate_physics_metrics(ball_positions, fps):
    metrics = {
        "speed_kmph": None,
        "speed_type": "unavailable",
        "speed_note": "insufficient_track",
        "swing_label": "straight",
        "swing_cm_pitch": 0.0,
        "swing_cm_impact": 0.0,
        "swing_deg": 0.0,
        "spin_label": "none",
        "spin_rpm": None,
        "spin_strength": 0.0,
        "spin_method": "trajectory",
        "release_index": 0,
        "pitch_index": 0,
        "impact_index": 0,
        "meters_per_px": None,
    }

    if not ball_positions or len(ball_positions) < 5:
        return metrics

    fps = float(fps) if fps and fps > 1 else 30.0
    pts, fwd, lat = _trajectory_axes(ball_positions)
    progress, lateral = _progress_and_lateral(pts, pts[0], fwd, lat)

    release_idx = _release_index(progress)
    impact_idx = len(pts) - 1
    if impact_idx <= release_idx:
        return metrics

    flight_px = float(progress[impact_idx] - progress[release_idx])
    if flight_px <= 1e-6:
        return metrics

    meters_per_px = CRICKET_PITCH_METERS / flight_px
    dt = (impact_idx - release_idx) / fps
    if dt > 1e-6:
        speed_kmph = (CRICKET_PITCH_METERS / dt) * 3.6
        metrics["speed_kmph"] = round(float(speed_kmph), 1)
        metrics["speed_type"] = "measured_22_yard_release_to_impact"
        metrics["speed_note"] = "distance=20.12m,time=(impact-release)/fps"

    pitch_idx = _pitch_index(lateral)
    pitch_idx = max(release_idx + 1, min(pitch_idx, impact_idx - 1))

    expected_lateral = np.linspace(float(lateral[release_idx]), float(lateral[impact_idx]), len(lateral))
    dev_pitch_px = float(lateral[pitch_idx] - expected_lateral[pitch_idx])
    dev_impact_px = float(lateral[impact_idx] - expected_lateral[impact_idx])
    dev_pitch_cm = dev_pitch_px * meters_per_px * 100.0
    dev_impact_cm = dev_impact_px * meters_per_px * 100.0
    swing_deg = math.degrees(math.atan2(abs(dev_impact_px), max(flight_px, 1e-6)))

    if abs(dev_impact_cm) < 1.0:
        swing_label = "straight"
    elif dev_impact_cm > 0:
        swing_label = "outswing"
    else:
        swing_label = "inswing"

    pre = pts[max(release_idx, pitch_idx - 4):pitch_idx + 1]
    post = pts[pitch_idx:min(len(pts), pitch_idx + 5)]
    spin_label = "none"
    spin_rpm = None
    spin_strength = 0.0
    if len(pre) >= 3 and len(post) >= 3:
        pre_vec = pre[-1] - pre[0]
        post_vec = post[-1] - post[0]
        pre_angle = math.atan2(float(pre_vec[1]), float(pre_vec[0]))
        post_angle = math.atan2(float(post_vec[1]), float(post_vec[0]))
        turn_rad = abs(post_angle - pre_angle)
        if turn_rad > math.pi:
            turn_rad = (2 * math.pi) - turn_rad

        post_dt = (len(post) - 1) / fps
        if post_dt > 1e-6:
            spin_rpm = (turn_rad / (2 * math.pi)) / post_dt * 60.0
            spin_strength = abs(float(post_vec @ lat)) / max(float(np.linalg.norm(post_vec)), 1e-6)
            if abs(float(post_vec @ lat)) > 1e-3:
                spin_label = "leg spin" if float(post_vec @ lat) > 0 else "off spin"
            if spin_rpm < 10.0:
                spin_label = "none"
                spin_strength = 0.0

    metrics.update({
        "swing_label": swing_label,
        "swing_cm_pitch": round(dev_pitch_cm, 2),
        "swing_cm_impact": round(dev_impact_cm, 2),
        "swing_deg": round(float(swing_deg), 2),
        "spin_label": spin_label,
        "spin_rpm": None if spin_rpm is None else round(float(spin_rpm), 1),
        "spin_strength": round(float(spin_strength), 3),
        "release_index": int(release_idx),
        "pitch_index": int(pitch_idx),
        "impact_index": int(impact_idx),
        "meters_per_px": float(meters_per_px),
    })
    return metrics


def detect_swing_x(ball_positions):
    positions, fps = _extract_track(ball_positions)
    return calculate_physics_metrics(positions, fps).get("swing_label", "straight")


def calculate_spin_real(ball_positions):
    positions, fps = _extract_track(ball_positions)
    metrics = calculate_physics_metrics(positions, fps)
    spin_label = metrics.get("spin_label", "none")
    if spin_label == "leg spin":
        return "leg-spin", metrics.get("spin_rpm") or 0.0
    if spin_label == "off spin":
        return "off-spin", metrics.get("spin_rpm") or 0.0
    return "none", 0.0


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
        tracked = track_ball_positions(video_path)
        ball_positions, video_fps = _extract_track(tracked)

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

        metrics = calculate_physics_metrics(ball_positions, video_fps)
        trajectory = build_trajectory(ball_positions, frame_width, frame_height)

        return {
            "status": "success",
            "speed_kmph": metrics.get("speed_kmph"),
            "speed_type": metrics.get("speed_type"),
            "speed_note": metrics.get("speed_note"),
            "swing": metrics.get("swing_label", "straight"),
            "swing_cm_pitch": metrics.get("swing_cm_pitch"),
            "swing_cm_impact": metrics.get("swing_cm_impact"),
            "swing_deg": metrics.get("swing_deg"),
            "spin": metrics.get("spin_label", "none"),
            "spin_rpm": metrics.get("spin_rpm"),
            "spin_strength": metrics.get("spin_strength", 0.0),
            "spin_method": metrics.get("spin_method"),
            "release_frame": metrics.get("release_index"),
            "pitch_frame": metrics.get("pitch_index"),
            "impact_frame": metrics.get("impact_index"),
            "fps": round(float(video_fps), 2),
            "trajectory": trajectory
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

    # --- USER IDENTIFICATION (Authorization only, no X-USER-ID fallback) ---
    user_id = None
    try:
        if credentials:
            user_id = verify_firebase_token(credentials.credentials)
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
        tracked = track_ball_positions(video_path)
        ball_positions, _ = _extract_track(tracked)

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
            "success": True,
            "reply": "Ask me anything about batting, bowling, mindset, or match situations 🏏",
            "premium_required": False
        }

    client = OpenAI(api_key=api_key)

    # --- USER IDENTIFICATION (Authorization only, no X-USER-ID fallback) ---
    user_id = None
    try:
        if credentials:
            user_id = verify_firebase_token(credentials.credentials)
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
            user_id = verify_firebase_token(credentials.credentials)
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
        tracked = track_ball_positions(video_path)
        ball_positions, tracked_fps = _extract_track(tracked)

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
        fps = cap.get(cv2.CAP_PROP_FPS) or tracked_fps or 30.0
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
    Project trajectory to the stump plane using a trajectory model.
    Returns:
      (hits_stumps: bool, confidence: float, projected_lateral_m: float|None)
    """

    if not ball_positions or len(ball_positions) < 6:
        return False, 0.0, None

    pts, fwd, lat = _trajectory_axes(ball_positions)
    progress, lateral = _progress_and_lateral(pts, pts[0], fwd, lat)
    release_idx = _release_index(progress)
    impact_idx = len(pts) - 1
    if impact_idx <= release_idx + 2:
        return False, 0.0, None

    flight_px = float(progress[impact_idx] - progress[release_idx])
    if flight_px <= 1e-6:
        return False, 0.0, None
    meters_per_px = CRICKET_PITCH_METERS / flight_px

    s_m = (progress - progress[release_idx]) * meters_per_px
    l_m = lateral * meters_per_px

    fit_end = max(release_idx + 4, min(impact_idx, len(pts) - 1))
    s_fit = s_m[release_idx:fit_end + 1]
    l_fit = l_m[release_idx:fit_end + 1]
    if len(s_fit) < 4:
        return False, 0.0, None

    coeff = np.polyfit(s_fit, l_fit, deg=2)
    stump_s = CRICKET_PITCH_METERS
    projected_lateral = float(np.polyval(coeff, stump_s))

    half_width = STUMP_WIDTH_METERS / 2.0
    hits_stumps = abs(projected_lateral) <= half_width

    residual = np.sqrt(np.mean((np.polyval(coeff, s_fit) - l_fit) ** 2))
    quality = max(0.0, 1.0 - min(residual / 0.20, 1.0))
    margin = max(0.0, 1.0 - min(abs(projected_lateral) / max(half_width, 1e-6), 1.0))
    confidence = round((0.6 * margin + 0.4 * quality), 2)
    return hits_stumps, confidence, projected_lateral

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
        tracked = track_ball_positions(video_path)
        ball_positions, _ = _extract_track(tracked)

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

        hits_stumps, stump_confidence, projected_lateral = detect_stump_hit_from_positions(
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
                "projected_lateral_m": projected_lateral,
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
