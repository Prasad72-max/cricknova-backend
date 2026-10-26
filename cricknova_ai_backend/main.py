print("🔥🔥🔥 RUNNING MAIN.PY (NUCLEAR FIX ACTIVE) 🔥🔥🔥")
import asyncio
import base64
import json
import mimetypes
import os
import sys
import time
from contextlib import suppress
from typing import Any

# Ensure the repo root (the directory containing this file) is on sys.path.
# Using the parent-of-parent can point outside the deployed repo on Render.
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)
from fastapi import UploadFile, File, HTTPException, Request, Form, WebSocket, WebSocketDisconnect
from cricknova_engine.processing.routes.payment_verify import router as subscription_router
from fastapi.middleware.cors import CORSMiddleware
import tempfile
import math
import numpy as np
import cv2
from gemini_text import generate_text
from pydantic import BaseModel
from fastapi import Body
from fastapi import FastAPI
from google.cloud import firestore
from google.genai import Client
from google.genai import types
from cricknova_engine.processing.firestore_db import get_firestore_client

app = FastAPI(
    title="CrickNova AI Backend",
    version="1.0.0"
)

from dotenv import load_dotenv
load_dotenv()

GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY") or os.getenv("GEMINI_API_KEY")
LIVE_FALLBACK_MODEL = "gemini-2.0-flash-exp"
_LIVE_MODEL_WHITELIST = {
    "gemini-2.0-flash-exp",
    "models/gemini-2.0-flash-exp",
    "gemini-2.0-flash-live-001",
    "models/gemini-2.0-flash-live-001",
    "gemini-2.5-flash-live",
    "models/gemini-2.5-flash-live",
    "gemini-3.1-flash-live-preview",
    "models/gemini-3.1-flash-live-preview",
    "gemini-flash-latest",
    "models/gemini-flash-latest",
    "gemini-2.5-flash-preview-09-2025",
    "models/gemini-2.5-flash-preview-09-2025",
}


def _resolve_live_model_name() -> str:
    raw = (os.getenv("LIVE_GEMINI_MODEL") or LIVE_FALLBACK_MODEL).strip()
    if raw in _LIVE_MODEL_WHITELIST:
        return raw
    return LIVE_FALLBACK_MODEL


LIVE_MODEL_NAME = _resolve_live_model_name()
LIVE_SYSTEM_INSTRUCTION = """Context & Role:
You are "CrickNova AI", an elite cricket coach giving short real-time feedback from the non-striker's end.
Keep every response under 25 words.
Speak naturally, briefly, and only when there is something useful to say.
If the shot is excellent, give a short confidence boost.
If there is a mistake, mention the main flaw and the instant fix.
"""

_live_firestore_client: firestore.Client | None = None
_live_gemini_client: Client | None = None


def _live_db() -> firestore.Client:
    global _live_firestore_client
    if _live_firestore_client is None:
        _live_firestore_client = get_firestore_client()
    return _live_firestore_client


def _live_doc(user_id: str):
    return _live_db().collection("users").document(user_id)


def _live_balance_ms_from_data(data: dict[str, Any]) -> int:
    if "live_milliseconds_remaining" in data:
        try:
            return max(0, int(data.get("live_milliseconds_remaining", 0)))
        except (TypeError, ValueError):
            return 0
    try:
        return max(0, int(data.get("live_seconds_remaining", 0)) * 1000)
    except (TypeError, ValueError):
        return 0


def _legacy_seconds(milliseconds: int) -> int:
    if milliseconds <= 0:
        return 0
    return (milliseconds + 999) // 1000


def _live_gemini() -> Client:
    global _live_gemini_client
    if _live_gemini_client is None:
        if not GOOGLE_API_KEY:
            raise RuntimeError("GOOGLE_API_KEY or GEMINI_API_KEY is required")
        _live_gemini_client = Client(
            api_key=GOOGLE_API_KEY,
            http_options={"api_version": "v1alpha"},
        )
    return _live_gemini_client


async def _get_live_balance_ms(user_id: str) -> int:
    def read() -> int:
        snap = _live_doc(user_id).get()
        return _live_balance_ms_from_data(snap.to_dict() if snap.exists else {})

    return await asyncio.to_thread(read)


async def _charge_live_elapsed_ms(user_id: str, elapsed_ms: int) -> int:
    @firestore.transactional
    def txn_body(transaction: firestore.Transaction) -> int:
        ref = _live_doc(user_id)
        snap = ref.get(transaction=transaction)
        current_ms = _live_balance_ms_from_data(snap.to_dict() if snap.exists else {})
        billed_ms = max(0, elapsed_ms)
        next_ms = max(0, current_ms - billed_ms)
        transaction.set(
            ref,
            {
                "live_milliseconds_remaining": next_ms,
                "live_seconds_remaining": _legacy_seconds(next_ms),
                "last_live_session_billed_ms": billed_ms,
                "last_live_session_ended_at": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        return next_ms

    def run() -> int:
        return txn_body(_live_db().transaction())

    return await asyncio.to_thread(run)


async def _live_billing_guard(
    client_ws: WebSocket,
    stop: asyncio.Event,
    start_ns: int,
    starting_balance_ms: int,
) -> None:
    while not stop.is_set():
        await asyncio.sleep(0.1)
        elapsed_ms = (time.monotonic_ns() - start_ns) // 1_000_000
        remaining_ms = max(0, starting_balance_ms - elapsed_ms)
        await client_ws.send_json(
            {
                "type": "billing",
                "live_milliseconds_remaining": remaining_ms,
                "live_seconds_remaining": _legacy_seconds(remaining_ms),
                "elapsed_milliseconds": elapsed_ms,
            }
        )
        if remaining_ms <= 0:
            await client_ws.send_json(
                {"type": "termination", "reason": "LIVE_BALANCE_EXHAUSTED"}
            )
            stop.set()
            await client_ws.close(code=4001)
            return


async def _live_from_flutter(client_ws: WebSocket, live_session: Any, stop: asyncio.Event) -> None:
    frame_count = 0

    async def send_video_frame(frame_bytes: bytes) -> None:
        nonlocal frame_count
        frame_count += 1
        # --- THE FIX: send frame WITH end_of_turn=True so Gemini responds ---
        # Every frame: send image content and signal end of turn so Gemini
        # immediately generates a coaching response.
        try:
            content = types.Content(
                parts=[types.Part.from_bytes(data=frame_bytes, mime_type="image/jpeg")],
                role="user",
            )
            await live_session.send(input=content, end_of_turn=True)
        except Exception:
            # Fallback: plain dict with end_of_turn=True
            try:
                await live_session.send(
                    input={"data": frame_bytes, "mime_type": "image/jpeg"},
                    end_of_turn=True,
                )
            except Exception:
                pass

    while not stop.is_set():
        message = await client_ws.receive()
        raw = message.get("bytes")
        text = message.get("text")

        if text is not None:
            payload = json.loads(text)
            kind = payload.get("type")
            if kind == "video":
                frame = base64.b64decode(payload["data"])
                await send_video_frame(frame)
            elif kind == "audio":
                audio = base64.b64decode(payload["data"])
                await live_session.send(input={"data": audio, "mime_type": "audio/pcm"},
                                        end_of_turn=True)
            elif kind == "user_text":
                spoken = str(payload.get("text", "")).strip()
                if spoken:
                    await live_session.send(input=spoken, end_of_turn=True)
            elif kind == "stop":
                stop.set()
                return
            continue

        if raw:
            await send_video_frame(raw)


async def _live_from_gemini(client_ws: WebSocket, live_session: Any, stop: asyncio.Event) -> None:
    async for response in live_session.receive():
        if stop.is_set():
            return
        server_content = getattr(response, "server_content", None)
        if server_content and getattr(server_content, "model_turn", None):
            for part in server_content.model_turn.parts:
                inline_data = getattr(part, "inline_data", None)
                if inline_data and inline_data.data:
                    await client_ws.send_bytes(inline_data.data)
                part_text = getattr(part, "text", None)
                if part_text:
                    await client_ws.send_json({"type": "transcript", "text": part_text})
        text = getattr(response, "text", None)
        if text:
            await client_ws.send_json({"type": "transcript", "text": text})


@app.websocket("/ws/live-nets/{user_id}")
async def live_nets_socket(websocket: WebSocket, user_id: str) -> None:
    try:
        await websocket.accept()
        starting_balance_ms = await _get_live_balance_ms(user_id)
        if starting_balance_ms <= 0:
            await websocket.send_json({"type": "termination", "reason": "NO_LIVE_BALANCE"})
            await websocket.close(code=4003)
            return

        await websocket.send_json(
            {
                "type": "ready",
                "live_milliseconds_remaining": starting_balance_ms,
                "live_seconds_remaining": _legacy_seconds(starting_balance_ms),
            }
        )

        stop = asyncio.Event()
        start_ns = time.monotonic_ns()
        billed = False

        # Read client config first to customize system instruction with correct language
        player_name = "Player"
        language = "English"
        discipline = "Batting"
        try:
            config_msg = await asyncio.wait_for(websocket.receive(), timeout=5.0)
            if config_msg.get("text"):
                payload = json.loads(config_msg["text"])
                if payload.get("type") == "client_config":
                    player_name = str(payload.get("name", player_name)).strip() or player_name
                    language = str(payload.get("language", language)).strip() or language
                    discipline = str(payload.get("discipline", discipline)).strip() or discipline
        except Exception as e:
            print(f"Failed to receive client_config: {e}")

        # Build dynamic system instruction using the user's preferred language and training mode
        dynamic_instruction = f"""Context & Role:
You are "CrickNova AI", a tough, high-energy, elite cricket coach standing at the non-striker's end talking directly into the earbuds of the player named {player_name}.
You see their live training frames ({discipline}) and give real-time coaching advice.
Format: Respond with exactly ONE complete punchy coaching line/sentence of 10 to 22 words. Do NOT output single words, bullet points, or formatting.

Strict Tone Rules:
1. If the shot/movement is GOOD: Be extremely happy, proud, and use encouraging, positive coaching language.
2. If the shot/movement is a MISTAKE/BAD: Be extremely strict, rude, harsh, and cruel. Point out the technical fault sharply and command an instant fix.

Language Rule:
You MUST respond only in {language}. For example, if the language is Marathi, speak in Marathi. If Hindi, speak in Hindi. If English, speak in English. Do not use any other language.
"""

        config = types.LiveConnectConfig(
            response_modalities=["TEXT"],
            system_instruction=dynamic_instruction,
        )

        async with _live_gemini().aio.live.connect(model=LIVE_MODEL_NAME, config=config) as session:
            await websocket.send_json(
                {
                    "type": "connected",
                    "model": LIVE_MODEL_NAME,
                }
            )
            with suppress(Exception):
                await session.send(
                    input=(
                        "Start live cricket detection now. Watch every incoming frame "
                        "and respond with one short coaching line whenever there is a "
                        "useful mistake, good shot, or setup cue. If the view is clear, "
                        "say one brief coaching observation right away."
                    ),
                    end_of_turn=True,
                )
            tasks = [
                asyncio.create_task(
                    _live_billing_guard(websocket, stop, start_ns, starting_balance_ms)
                ),
                asyncio.create_task(_live_from_flutter(websocket, session, stop)),
                asyncio.create_task(_live_from_gemini(websocket, session, stop)),
            ]
            done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            stop.set()
            for task in pending:
                task.cancel()
            for task in done:
                with suppress(WebSocketDisconnect):
                    task.result()
            elapsed_ms = min(
                starting_balance_ms,
                (time.monotonic_ns() - start_ns) // 1_000_000,
            )
            await _charge_live_elapsed_ms(user_id, elapsed_ms)
            billed = True
    except WebSocketDisconnect:
        with suppress(Exception):
            stop.set()
    except Exception as exc:
        with suppress(Exception):
            await websocket.send_json(
                {
                    "type": "error",
                    "reason": f"Live AI backend error: {exc}",
                }
            )
            await websocket.close(code=1011)
    finally:
        with suppress(Exception):
            stop.set()
        if "starting_balance_ms" in locals() and "start_ns" in locals() and not billed:
            elapsed_ms = min(
                starting_balance_ms,
                (time.monotonic_ns() - start_ns) // 1_000_000,
            )
            with suppress(Exception):
                await _charge_live_elapsed_ms(user_id, elapsed_ms)

try:
    from subscriptions_store import get_current_user
except ImportError:
    def get_current_user(authorization: str | None = None):
        if not authorization:
            return None
        if authorization.lower().startswith("bearer "):
            return authorization.split(" ", 1)[1]
        return authorization
import razorpay
RAZORPAY_KEY_ID = os.getenv("RAZORPAY_KEY_ID")
RAZORPAY_KEY_SECRET = os.getenv("RAZORPAY_KEY_SECRET")
razorpay_client = None
if RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET:
    razorpay_client = razorpay.Client(auth=(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET))


def razorpay_ready():
    return bool(RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET)




from cricknova_engine.processing.ball_tracker_motion import track_ball_positions
import time

# Subscription management (external store)
from subscriptions_store import (
    get_subscription,
    is_subscription_active,
    increment_chat,
    increment_mistake,
    increment_compare
)


# -----------------------------
# TRAJECTORY NORMALIZATION
# -----------------------------
def build_trajectory(ball_positions, frame_width, frame_height):
    if not ball_positions or frame_width <= 0 or frame_height <= 0:
        return []
    out = []
    prev = None
    for i, (x, y) in enumerate(ball_positions):
        nx = float(x) / float(frame_width)
        ny = float(y) / float(frame_height)
        nx = max(0.0, min(1.0, nx))
        ny = max(0.0, min(1.0, ny))
        if prev is not None and abs(prev[0] - nx) < 1e-4 and abs(prev[1] - ny) < 1e-4:
            continue
        out.append({"x": nx, "y": ny, "frame": i})
        prev = (nx, ny)
    return out


def estimate_speed_fallback(ball_positions, fps, frame_height):
    """
    Real (non-scripted) fallback speed from tracked pixel motion.
    Used only when strict pre-pitch speed extraction fails.
    """
    if not ball_positions or len(ball_positions) < 3 or fps is None or fps <= 1:
        return None

    fps = float(max(20.0, min(60.0, fps)))

    diffs = []
    for i in range(1, len(ball_positions)):
        x1, y1 = ball_positions[i - 1]
        x2, y2 = ball_positions[i]
        d = math.hypot(x2 - x1, y2 - y1)
        if 1.0 < d < 220.0:
            diffs.append(d)
    if len(diffs) < 2:
        return None

    med_px = float(np.median(diffs))
    ys = [p[1] for p in ball_positions]
    y_span = float(max(ys) - min(ys))
    if y_span < 24.0:
        y_span = 24.0

    # Map observed vertical travel span to ~18m effective flight distance.
    meters_per_px = 18.0 / y_span
    kmph = med_px * fps * meters_per_px * 3.6 * SPEED_CALIBRATION_FACTOR

    if kmph <= 0 or math.isnan(kmph) or math.isinf(kmph):
        return None

    return round(float(max(45.0, min(170.0, kmph))), 1)


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
    user_id = get_current_user(
        authorization=request.headers.get("Authorization")
    )
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

    return {
        "premium": is_subscription_active(sub),
        "plan": sub.get("plan"),
        "limits": sub.get("limits"),
        "expiry": sub.get("expiry").isoformat() if sub.get("expiry") else None
    }



# -----------------------------
# ROOT HEALTH CHECK
# -----------------------------
@app.get("/")
def root():
    return {
        "status": "CrickNova AI Backend Running",
        "message": "Use /docs for API testing or POST /training/analyze for video analysis"
    }


@app.get("/__alive")
def alive():
    return {"alive": True, "service": "cricknova-backend"}



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

    from subscriptions_store import create_or_update_subscription

    create_or_update_subscription(
        user_id=req.user_id,
        plan=req.plan,
        payment_id=req.razorpay_payment_id,
        order_id=req.razorpay_order_id
    )

    from subscriptions_store import get_subscription

    sub = get_subscription(req.user_id)

    return {
        "status": "success",
        "premium": True,
        "user_id": req.user_id,
        "plan": sub.get("plan"),
        "limits": sub.get("limits"),
        "expiry": sub.get("expiry").isoformat() if sub.get("expiry") else None
    }


# -----------------------------
# SPEED CALIBRATION (REALISTIC)
# -----------------------------
# Broadcast-calibrated factor to align with international speeds
# Derived from comparison with Hawk-Eye / broadcast averages
SPEED_CALIBRATION_FACTOR = 0.92
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
async def analyze_training_video(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        tmp.write(await file.read())
        video_path = tmp.name

    try:
        ball_positions = track_ball_positions(video_path)

        # Use ONLY the first ball delivery (no best-ball logic)
        if len(ball_positions) > 30:
            ball_positions = ball_positions[:30]

        if len(ball_positions) < 3:
            return {
                "status": "failed",
                "reason": "Ball not detected clearly",
                "speed_kmph": None,
                "speed_type": "unavailable",
                "speed_note": "INSUFFICIENT_TRACK_POINTS",
                "swing": "unknown",
                "spin": "unknown",
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
            if len(ball_positions) < 8 or fps <= 1:
                return None

            # ---- FPS normalization ----
            fps = min(max(fps, 24), 60)

            # ---- Use only PRE-PITCH frames ----
            ys = [p[1] for p in ball_positions]
            pitch_idx = int(np.argmax(ys))
            usable = ball_positions[max(0, pitch_idx - 8):pitch_idx]

            if len(usable) < 5:
                return None

            # ---- Per-frame distances ----
            distances = []
            for i in range(1, len(usable)):
                x1, y1 = usable[i - 1]
                x2, y2 = usable[i]
                d = math.hypot(x2 - x1, y2 - y1)

                # Tight noise rejection
                if 1.5 < d < 35.0:
                    distances.append(d)

            if len(distances) < 4:
                return None

            # ---- Trimmed median (remove extreme noise) ----
            distances.sort()
            trim = int(len(distances) * 0.2)
            core = distances[trim:len(distances) - trim]
            if not core:
                return None

            median_px = float(np.median(core))

            # ---- Pitch length scaling (camera adaptive) ----
            pitch_px = max(220.0, np.percentile(ys, 90) - np.percentile(ys, 10))
            meters_per_pixel = 20.12 / pitch_px

            speed_mps = median_px * meters_per_pixel * fps
            speed_kmph = speed_mps * 3.6 * SPEED_CALIBRATION_FACTOR

            # ICC realistic bowling range
            if speed_kmph < 80 or speed_kmph > 160:
                return None

            return round(speed_kmph, 1)

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
        speed_type = "pre-pitch"
        speed_note = "Pre-pitch release speed, broadcast-calibrated for realistic international comparison"
        if raw_speed is None:
            raw_speed = estimate_speed_fallback(ball_positions, video_fps, frame_height)
            if raw_speed is not None:
                speed_type = "trajectory_fallback"
                speed_note = "Fallback from real tracked trajectory (non-scripted)"

        # IMPORTANT:
        # Do NOT force 0.0 when speed is not detected.
        # Return None so the app can distinguish "no data" vs real zero.
        speed_kmph = round(raw_speed, 1) if raw_speed is not None else None

        swing = detect_swing_x(ball_positions)
        spin_name, spin_turn = calculate_spin_real(ball_positions)
        trajectory = build_trajectory(ball_positions, frame_width, frame_height)

        # Normalize spin output for app (leg spin / off spin / none)
        if spin_name == "leg-spin":
            spin_label = "leg spin"
        elif spin_name == "off-spin":
            spin_label = "off spin"
        else:
            spin_label = "none"

        return {
            "status": "success",
            "cricket_detected": True,
            "cricket_summary": verification_summary,
            "speed_kmph": speed_kmph,
            "speed_type": speed_type,
            "speed_note": speed_note,
            "swing": swing,
            "spin": spin_label,
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
    discipline: str | None = Form(None),
    prompt: str | None = Form(None),
):
    from nvidia_client import is_nvidia_available, generate_nvidia_vision
    if not is_nvidia_available():
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")

    # ---- Subscription/Mistake Limit Check ----
    user_id = get_current_user(
        authorization=request.headers.get("Authorization")
    )
    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    from subscriptions_store import get_subscription, is_subscription_active, increment_mistake
    sub = get_subscription(user_id)

    # HARD BLOCK: no subscription record or inactive subscription
    if not sub or not is_subscription_active(sub):
        raise HTTPException(
            status_code=403,
            detail="PREMIUM_REQUIRED"
        )
    if sub["mistake_used"] >= sub.get("limits", {}).get("mistake", 0):
        raise HTTPException(status_code=403, detail="MISTAKE_LIMIT_REACHED")
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        video_bytes = await file.read()
        tmp.write(video_bytes)
        video_path = tmp.name

    try:
        disc_label = (discipline or "").strip().lower()
        if disc_label not in ("batting", "bowling"):
            disc_label = "cricket"

        if not video_bytes:
            raise HTTPException(status_code=422, detail="VIDEO_EMPTY")

        coaching_prompt = (prompt or "").strip() or f"""
Inspect the attached video before coaching. First decide from visible evidence whether this is a cricket clip and whether a {disc_label} action is clearly visible.
If it is not cricket, or the requested {disc_label} action is not visible, do not give cricket technique advice. Return only JSON with cricket_detected=false and observation describing what is actually visible and why cricket coaching cannot be given.
If the requested cricket action is visible, return only JSON with cricket_detected=true, exactly two video-grounded mistakes, one specific impact explaining their likely performance consequence, and one practical drill that addresses them. Do not infer a player's body position, bat, ball, or action unless visible in the frames. If evidence is unclear, say so in observation and do not invent mistakes.
Required JSON shape for a clear cricket action: {{"cricket_detected":true,"mistakes":["...","..."],"impact":"...","drill":"..."}}.
Required JSON shape otherwise: {{"cricket_detected":false,"observation":"..."}}.
"""

        feedback = generate_nvidia_vision(
            prompt=coaching_prompt,
            video_bytes=video_bytes,
            video_mime_type=(file.content_type if file.content_type and file.content_type.startswith("video/") else mimetypes.guess_type(file.filename or "")[0] or "video/mp4"),
            system_instruction="Inspect the provided video. Give cricket coaching only when the requested cricket action is visibly present. Never invent visual evidence.",
            max_output_tokens=1200,
            temperature=0.2,
        )
        if not feedback.strip():
            raise HTTPException(status_code=502, detail="AI_EMPTY_RESPONSE")
        increment_mistake(user_id)

        return {
            "status": "success",
            "coach_feedback": feedback,
            "reply": feedback,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail="AI_ANALYSIS_FAILED") from e

    finally:
        if os.path.exists(video_path):
            os.remove(video_path)


# -----------------------------
# AI COACH CHAT (TEXT ONLY, JSON)
# -----------------------------
class CoachChatRequest(BaseModel):
    message: str | None = None
    history: list[dict] | None = None

@app.post("/coach/chat")
async def ai_coach_chat(request: Request, req: CoachChatRequest = Body(...)):
    from nvidia_client import is_nvidia_available
    if not is_nvidia_available():
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")

    message = (req.message or "").strip()
    history = req.history or []

    if not message:
        return {
            "status": "success",
            "reply": "Ask me anything about batting, bowling, mindset, or match situations 🏏"
        }

    # ---- Subscription/Chat Limit Check ----
    user_id = get_current_user(
        authorization=request.headers.get("Authorization")
    )
    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    from subscriptions_store import get_subscription, is_subscription_active, increment_chat
    sub = get_subscription(user_id)
    if not is_subscription_active(sub):
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")
    if sub["chat_used"] >= sub.get("limits", {}).get("chat", 0):
        raise HTTPException(status_code=403, detail="CHAT_LIMIT_REACHED")
    increment_chat(user_id)
    try:
        msg_lower = message.lower()
        looks_like_raw_prompt = (
            "output json" in msg_lower
            or "output json schema" in msg_lower
            or "json strictly" in msg_lower
            or "\"rating\"" in msg_lower
            or "clip context" in msg_lower
            or "clip:" in msg_lower
            or "trackingpoints:" in msg_lower
            or "trajectorysignature:" in msg_lower
            or "requestutc:" in msg_lower
            or "coaching task" in msg_lower
            or "valid json" in msg_lower
            or "[mistakes]" in msg_lower
            or "[how to fix]" in msg_lower
            or "[drill]" in msg_lower
        )

        if looks_like_raw_prompt:
            is_bowling_prompt = "bowling" in msg_lower and "batting-only" not in msg_lower
            discipline_label = "bowling" if is_bowling_prompt else "batting"
            reply_text = generate_text(
                system_instruction=f"You are a universal cricket coach specializing in {discipline_label} analysis. Analyze the clip context and return the requested json format.",
                user_prompt=message,
                max_output_tokens=1600,
                temperature=0.45,
            )
            return {"status": "success", "reply": reply_text}

        # ⚡ Direct CricX Chat: "You are a universal cricket coach."
        messages_payload = [
            {
                "role": "system",
                "content": "You are a universal cricket coach. Keep your responses focused on cricket.",
            }
        ]
        for item in history[-12:]:
            if not isinstance(item, dict):
                continue
            role = "user" if str(item.get("role", "user")).strip().lower() == "user" else "assistant"
            content = str(item.get("content", "")).strip()
            if content:
                messages_payload.append({"role": role, "content": content})

        messages_payload.append({"role": "user", "content": message})

        from nvidia_client import call_nvidia_chat
        reply_text = call_nvidia_chat(
            messages_payload,
            max_tokens=1600,
            temperature=0.6,
        )

        return {
            "status": "success",
            "reply": reply_text
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
    prompt: str | None = Form(None),
    discipline: str | None = Form(None),
):
    from nvidia_client import is_nvidia_available
    if not is_nvidia_available():
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")

    # ---- Subscription/Compare Limit Check ----
    user_id = get_current_user(
        authorization=request.headers.get("Authorization")
    )
    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")

    from subscriptions_store import get_subscription, is_subscription_active, increment_compare
    sub = get_subscription(user_id)
    if not is_subscription_active(sub):
        raise HTTPException(status_code=403, detail="PREMIUM_REQUIRED")
    if sub["compare_used"] >= sub.get("limits", {}).get("compare", 0):
        raise HTTPException(status_code=403, detail="COMPARE_LIMIT_REACHED")
    def save_temp(file):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
        tmp.write(file.file.read())
        tmp.close()
        return tmp.name

    left_path = save_temp(left)
    right_path = save_temp(right)

    def trajectory_signature(points):
        if not points:
            return "none"
        xs = [float(p[0]) for p in points if len(p) >= 2]
        ys = [float(p[1]) for p in points if len(p) >= 2]
        if not xs or not ys:
            return "none"
        x_min, x_max = min(xs), max(xs)
        y_min, y_max = min(ys), max(ys)
        bounce_i = ys.index(y_max)
        tail_start = max(0, int(len(xs) * 0.80))
        tail = xs[tail_start:] if tail_start < len(xs) else xs[-1:]
        tail_mean = sum(tail) / max(1, len(tail))
        curve = 0.0
        if len(xs) >= 3:
            curve = max(
                abs((xs[i + 2] - xs[i + 1]) - (xs[i + 1] - xs[i]))
                for i in range(0, len(xs) - 2)
            )
        return (
            f"n={len(xs)} "
            f"x={x_min:.2f}-{x_max:.2f} "
            f"y={y_min:.2f}-{y_max:.2f} "
            f"bounce={bounce_i} "
            f"tailX={tail_mean:.2f} "
            f"curve={curve:.4f}"
        )

    try:
        from nvidia_client import generate_nvidia_comparison_vision
        with open(left_path, "rb") as left_file:
            left_video_bytes = left_file.read()
        with open(right_path, "rb") as right_file:
            right_video_bytes = right_file.read()
        if not left_video_bytes or not right_video_bytes:
            raise HTTPException(status_code=422, detail="VIDEO_EMPTY")

        base_prompt = (prompt or "").strip()
        if not base_prompt:
            base_prompt = """
Compare the player's two video clips honestly in natural coaching language.
Do not force Video 2 to be better than Video 1.
Explain what improved, what is still weak, and what to do next.
Give exactly 2 practical drills.
- Do not mention speed, swing, or spin.
- Keep it specific to what changed between the two clips.
Do not give rating/score.
"""

        discipline_text = (discipline or "").strip().lower()
        if discipline_text not in ("batting", "bowling"):
            prompt_lower = base_prompt.lower()
            discipline_text = "bowling" if "bowling" in prompt_lower and "batting-only" not in prompt_lower else "batting"

        diff_text = generate_nvidia_comparison_vision(
            prompt=base_prompt,
            left_video_bytes=left_video_bytes,
            right_video_bytes=right_video_bytes,
            left_video_mime_type=(left.content_type if left.content_type and left.content_type.startswith("video/") else mimetypes.guess_type(left.filename or "")[0] or "video/mp4"),
            right_video_mime_type=(right.content_type if right.content_type and right.content_type.startswith("video/") else mimetypes.guess_type(right.filename or "")[0] or "video/mp4"),
            system_instruction="Inspect both attached videos. Report only visible cricket evidence and never invent actions or technique.",
            max_output_tokens=1800,
            temperature=0.2,
        )
        if not diff_text.strip():
            raise HTTPException(status_code=502, detail="AI_EMPTY_RESPONSE")
        increment_compare(user_id)

        return {
            "status": "success",
            "difference": diff_text
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail="AI_ANALYSIS_FAILED") from e

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
        speed_type = "broadcast-adjusted"
        speed_note = "Broadcast-style speed calibrated to match international match readings"
        if raw_speed is None:
            raw_speed = estimate_speed_fallback(ball_positions, fps, frame_height)
            if raw_speed is not None:
                speed_type = "trajectory_fallback"
                speed_note = "Fallback from real tracked trajectory (non-scripted)"
        speed_kmph = raw_speed if raw_speed is not None else None
        swing = detect_swing_x(ball_positions)
        spin_name, _ = calculate_spin_real(ball_positions)
        trajectory = build_trajectory(ball_positions, frame_width, frame_height)

        if spin_name == "leg-spin":
            spin_label = "leg spin"
        elif spin_name == "off-spin":
            spin_label = "off spin"
        else:
            spin_label = "none"

        return {
            "status": "success",
            "cricket_detected": True,
            "cricket_summary": verification_summary,
            "speed_kmph": speed_kmph,
            "speed_type": speed_type,
            "speed_note": speed_note,
            "swing": swing,
            "spin": spin_label,
            "trajectory": trajectory
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
