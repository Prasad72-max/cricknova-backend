import os
import sys
import asyncio
import base64
import json
import math
import re
import time
import tempfile
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
from contextlib import suppress
from datetime import datetime, timedelta, timezone
from typing import Any
print("💤😡💀")
# Ensure the repo root (the directory containing this file) is on sys.path.
# Using the parent-of-parent can point outside the deployed repo on Render.
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

app = FastAPI(title="CrickNova AI Backend")

STRICT_POLICY_NOTICE = (
    "NON-CRICKET CONTENT DETECTED.\n\n"
    "This session has been terminated immediately. No feedback will be generated, "
    "used time will not be refunded, and this violation has been recorded against your account.\n\n"
    "Repeated violations will lock all CrickNova AI and paid features for 27 days."
)

FINAL_POLICY_WARNING_NOTICE = (
    "FINAL WARNING: NON-CRICKET CONTENT DETECTED.\n\n"
    "This session has been terminated with no refund and another violation has been recorded. "
    "Continue uploading non-cricket content and every CrickNova AI and paid feature "
    "will be locked for 27 days."
)

EDGE_POLICY_BAN_NOTICE = (
    "ACCOUNT LOCKED FOR 27 DAYS.\n\n"
    "Repeated non-cricket uploads triggered an account restriction. "
    "All CrickNova AI and paid features are disabled until the lock expires."
)

UPLOAD_NON_CRICKET_NOTICE = (
    "This does not look like a cricket training clip. "
    "Please upload a clear batting, bowling, fielding, wicketkeeping, "
    "or cricket practice video for accurate CrickNova analysis."
)

@app.get("/__alive")
def alive():
    return {
        "alive": True,
        "file": "spacefoco_backend.py",
        "live_model": LIVE_MODEL_NAME,
        "skip_billing": os.getenv("SKIP_BILLING", "false").lower() in ("true", "1", "yes"),
        "has_google_credentials": bool(os.getenv("GOOGLE_APPLICATION_CREDENTIALS")),
    }

@app.get("/__test_gemini")
async def test_gemini():
    try:
        api_key = _current_gemini_api_key()
        if not api_key:
            return {"success": False, "error": "No API key configured in environment variables (GOOGLE_API_KEY and GEMINI_API_KEY are empty)"}
        
        client = Client(api_key=api_key)
        # Try a simple text prompt first to check key and client
        model_name = _resolve_vision_model_name()
        resp = client.models.generate_content(
            model=model_name,
            contents="Say hello in Marathi in exactly 5 words."
        )
        return {
            "success": True,
            "response": getattr(resp, "text", str(resp)),
            "test_model": model_name,
            "resolved_vision_model": _resolve_vision_model_name(),
            "resolved_live_model": _resolve_live_model_name()
        }
    except Exception as e:
        import traceback
        return {
            "success": False,
            "error": str(e),
            "traceback": traceback.format_exc()
        }
from fastapi import UploadFile, File, HTTPException, Request, Form
from cricknova_engine.processing.routes.payment_verify import router as subscription_router
from fastapi.middleware.cors import CORSMiddleware
import tempfile
import math
import numpy as np
import cv2
from gemini_text import generate_text
from google.cloud import firestore
from google.genai import Client
from google.genai import types
from cricknova_engine.processing.firestore_db import get_firestore_client
 
from pydantic import BaseModel
from fastapi import Body
from dotenv import load_dotenv
load_dotenv()

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




from cricknova_engine.processing.ball_tracker_motion import (
    track_ball_observations,
    track_ball_positions,
)
import time

# Subscription management (external store)
from subscriptions_store import (
    get_subscription,
    is_subscription_active,
    increment_chat,
    increment_mistake,
    increment_compare
)


def _parse_expiry(raw_expiry):
    if raw_expiry is None:
        return None
    if hasattr(raw_expiry, "to_datetime"):
        try:
            raw_expiry = raw_expiry.to_datetime()
        except Exception:
            return None
    if hasattr(raw_expiry, "isoformat") and not isinstance(raw_expiry, str):
        try:
            raw_expiry = raw_expiry.isoformat()
        except Exception:
            return None
    if isinstance(raw_expiry, str):
        value = raw_expiry.strip()
        if not value:
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except Exception:
            try:
                return datetime.fromisoformat(value.replace("Z", ""))
            except Exception:
                return None
    return None


def resolve_request_user_id(request, req_user_id=None):
    return (
        request.headers.get("X-USER-ID")
        or request.headers.get("x-user-id")
        or request.headers.get("X-User-Id")
        or req_user_id
    )


def subscription_is_active_relaxed(sub):
    if not sub:
        return False
    plan = str(sub.get("plan") or "").strip().upper()
    if not plan or plan == "FREE":
        return False
    expiry = _parse_expiry(sub.get("expiry"))
    if expiry is None:
        return False
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc) < expiry


# -----------------------------
# TRAJECTORY NORMALIZATION
# -----------------------------
def build_trajectory(ball_positions, frame_width, frame_height):
    if not ball_positions or frame_width <= 0 or frame_height <= 0:
        return []
    trajectory = []
    for index, item in enumerate(ball_positions):
        if isinstance(item, dict):
            x = float(item.get("x", 0.0))
            y = float(item.get("y", 0.0))
            frame = int(item.get("frame", index))
        else:
            x = float(item[0])
            y = float(item[1])
            frame = index
        trajectory.append(
            {
                "x": max(0.0, min(1.0, x / float(frame_width))),
                "y": max(0.0, min(1.0, y / float(frame_height))),
                "frame": frame,
            }
        )
    return trajectory


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
    "gemini-live-2.5-flash-preview",
    "models/gemini-live-2.5-flash-preview",
    "gemini-flash-latest",
    "models/gemini-flash-latest",
}

VISION_FALLBACK_MODEL = "gemini-2.5-flash-lite"
_VISION_MODEL_WHITELIST = {
    "gemini-2.0-flash",
    "models/gemini-2.0-flash",
    "gemini-1.5-flash",
    "models/gemini-1.5-flash",
    "gemini-2.5-flash",
    "models/gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "models/gemini-2.5-flash-lite",
    "gemini-2.5-flash-preview-06-17",
    "models/gemini-2.5-flash-preview-06-17",
    "gemini-3.5-flash",
    "models/gemini-3.5-flash",
}


def _resolve_live_model_name() -> str:
    raw = (os.getenv("LIVE_GEMINI_MODEL") or LIVE_FALLBACK_MODEL).strip()
    if raw in _LIVE_MODEL_WHITELIST:
        return raw
    return LIVE_FALLBACK_MODEL


def _resolve_vision_model_name() -> str:
    raw = (os.getenv("LIVE_VISION_MODEL") or VISION_FALLBACK_MODEL).strip()
    if raw in _VISION_MODEL_WHITELIST:
        return raw
    return VISION_FALLBACK_MODEL


def _vision_model_candidates() -> list[str]:
    seen: set[str] = set()
    candidates: list[str] = []
    for model in (
        _resolve_vision_model_name(),
        "gemini-2.0-flash",
        "gemini-1.5-flash",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
    ):
        if model in _VISION_MODEL_WHITELIST and model not in seen:
            seen.add(model)
            candidates.append(model)
    return candidates


LIVE_MODEL_NAME = _resolve_live_model_name()
LIVE_SYSTEM_INSTRUCTION = """Context & Role:
You are CrickNova Elite Coach, a real professional cricket coach standing beside the player during practice.
Speak naturally, confidently, and directly like a human academy coach.
Never speak in fragments.
Always explain why the visible action is good or wrong.
"""

_live_firestore_client: firestore.Client | None = None
_live_gemini_client: Client | None = None
_live_vision_client: Client | None = None
_vision_key_index = 0


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
        _live_gemini_client = Client(
            api_key=_current_gemini_api_key(),
            http_options={"api_version": "v1alpha"},
        )
    return _live_gemini_client


def _gemini_api_keys() -> list[str]:
    keys: list[str] = []
    for env_name in ("GEMINI_API_KEYS", "GOOGLE_API_KEYS"):
        raw = os.getenv(env_name, "")
        for item in re.split(r"[,\s]+", raw):
            clean = item.strip()
            if clean and clean not in keys:
                keys.append(clean)
    for index in range(1, 11):
        for env_name in (
            f"GEMINI_API_KEY_{index}",
            f"GOOGLE_API_KEY_{index}",
            f"GEMINI_KEY_{index}",
            f"GOOGLE_KEY_{index}",
        ):
            clean = (os.getenv(env_name) or "").strip()
            if clean and clean not in keys:
                keys.append(clean)
    for env_name in ("GOOGLE_API_KEY", "GEMINI_API_KEY"):
        clean = (os.getenv(env_name) or "").strip()
        if clean and clean not in keys:
            keys.append(clean)
    return keys


def _current_gemini_api_key() -> str:
    keys = _gemini_api_keys()
    if not keys:
        raise RuntimeError("GOOGLE_API_KEY or GEMINI_API_KEY is required")
    return keys[_vision_key_index % len(keys)]


def _vision_gemini() -> Client:
    global _live_vision_client
    if _live_vision_client is None:
        _live_vision_client = Client(api_key=_current_gemini_api_key())
    return _live_vision_client


def _rotate_vision_key() -> None:
    global _vision_key_index, _live_vision_client
    keys = _gemini_api_keys()
    if not keys:
        return
    _vision_key_index = (_vision_key_index + 1) % len(keys)
    _live_vision_client = Client(api_key=keys[_vision_key_index])
    print(f"GEMINI_KEY_ROTATED active_index={_vision_key_index + 1}/{len(keys)}")


def _generate_vision_content_with_key_rotation(
    *,
    model: str,
    contents: Any,
    config: Any,
) -> Any:
    keys = _gemini_api_keys()
    if not keys:
        raise RuntimeError("GOOGLE_API_KEY or GEMINI_API_KEY is required")
    global _vision_key_index, _live_vision_client
    last_quota_error: Exception | None = None
    for offset in range(len(keys)):
        key_index = (_vision_key_index + offset) % len(keys)
        client = Client(api_key=keys[key_index])
        try:
            response = client.models.generate_content(
                model=model,
                contents=contents,
                config=config,
            )
            _vision_key_index = key_index
            _live_vision_client = client
            if offset > 0:
                print(f"GEMINI_KEY_RECOVERED active_index={key_index + 1}/{len(keys)}")
            return response
        except Exception as exc:
            if _is_gemini_quota_error(exc):
                last_quota_error = exc
                print(
                    f"GEMINI_KEY_QUOTA_EXHAUSTED index={key_index + 1}/{len(keys)} "
                    f"model={model}: {exc}"
                )
                continue
            raise
    raise RuntimeError(f"GEMINI_ALL_KEYS_QUOTA_EXHAUSTED: {last_quota_error}")


def _role_prompt(role: str) -> str:
    role = (role or "").strip().lower()
    if "bowl" in role:
        return (
            "Focus on bowling only. Mention run-up, front arm, wrist position, seam, "
            "release, line, length, and body alignment. "
            "Do not use batting advice."
        )
    return (
        "Focus on batting only. Mention stance, balance, bat path, "
        "timing, footwork, body alignment, and shot selection. "
        "Do not use bowling advice."
    )


def _spoken_player_name(coach_name: str) -> str:
    clean = " ".join((coach_name or "").strip().split())
    if not clean or clean.lower() == "player":
        return "Player"
    return clean.split(" ", 1)[0][:24]


def _normalize_live_language(language: str) -> str:
    value = (language or "").strip().lower()
    if "hindi" in value:
        return "Hindi"
    if "marathi" in value:
        return "Marathi"
    return "English"


def _clean_live_reply(raw_text: str) -> tuple[str, str]:
    text = " ".join((raw_text or "").replace("\n", " ").split()).strip()
    mood = ""
    tag_match = re.match(
        r"^\s*[\[\(\{]?\s*(praise|correction)\s*[\]\)\}]?\s*[:\-–—,]*\s*",
        text,
        flags=re.IGNORECASE,
    )
    if tag_match:
        mood = tag_match.group(1).lower()
        text = text[tag_match.end():].strip()
    text = re.sub(
        r"^\s*[\[\]\(\)\{\,\s]*(praise|correction)?[\]\(\)\{\,\s:;\-–—]*",
        "",
        text,
        flags=re.IGNORECASE,
    ).strip()
    return text, mood


def _extract_gemini_text(response: Any) -> str:
    text = (getattr(response, "text", None) or "").strip()
    if text:
        return text
    candidates = getattr(response, "candidates", None) or []
    for index, candidate in enumerate(candidates):
        finish_reason = getattr(candidate, "finish_reason", None)
        print(f"⚠️ Gemini candidate {index} finish_reason={finish_reason}")
        content = getattr(candidate, "content", None)
        if not content:
            continue
        for part in getattr(content, "parts", None) or []:
            part_text = getattr(part, "text", None)
            if part_text:
                return str(part_text).strip()
    return ""


def _is_usable_gemini_reply(text: str) -> bool:
    clean = " ".join((text or "").split()).strip()
    if not clean:
        return False
    if clean.upper().replace(" ", "_") in {
        "NO_CRICKET_ACTION",
        "STRICT_POLICY_VIOLATION",
    }:
        return False
    if len(clean) < 12:
        return False
    if len(re.findall(r"\w+", clean, flags=re.UNICODE)) < 3:
        return False
    if re.fullmatch(r"[\W_]+", clean, flags=re.UNICODE):
        return False
    return True


def _extract_usable_gemini_text(response: Any) -> str:
    text = _extract_gemini_text(response)
    if text.strip().upper().replace(" ", "_") in {
        "NO_CRICKET_ACTION",
        "STRICT_POLICY_VIOLATION",
    }:
        return "STRICT_POLICY_VIOLATION"
    if _is_usable_gemini_reply(text):
        return text
    if text:
        print(f"GEMINI_FRAGMENT_RESPONSE text={text}")
    return ""


def _is_gemini_quota_error(exc: Exception) -> bool:
    text = str(exc)
    return "429" in text or "RESOURCE_EXHAUSTED" in text or "quota" in text.lower()


def _edge_policy_ban_status(user_id: str) -> dict[str, Any] | None:
    try:
        snapshot = _live_db().collection("users").document(user_id).get()
        data = snapshot.to_dict() or {}
        banned_until = data.get("edge_policy_banned_until")
        if isinstance(banned_until, datetime):
            now = datetime.now(timezone.utc)
            if banned_until.tzinfo is None:
                banned_until = banned_until.replace(tzinfo=timezone.utc)
            if banned_until > now:
                return {
                    "status": "policy_banned",
                    "text": EDGE_POLICY_BAN_NOTICE,
                    "banned_until": banned_until.isoformat(),
                }
    except Exception as exc:
        print(f"EDGE_POLICY_BAN_CHECK_FAILED user={user_id}: {exc}")
    return None


def _reject_if_edge_banned(user_id: str) -> dict[str, Any] | None:
    ban_status = _edge_policy_ban_status(user_id)
    if ban_status is None:
        return None
    return {
        "status": "policy_banned",
        "text": ban_status["text"],
        "mood": "policy_violation",
        "refund_minutes": False,
        "terminate_session": True,
        "banned_until": ban_status.get("banned_until"),
    }


def _reject_if_any_ai_banned(user_id: str) -> dict[str, Any] | None:
    try:
        snapshot = _live_db().collection("users").document(user_id).get()
        data = snapshot.to_dict() or {}
        banned = (
            data.get("edge_policy_banned") == True
            or data.get("is_banned") == True
            or data.get("account_banned") == True
        )
        ban_until_keys = [
            "edge_policy_banned_until",
            "banned_until",
            "account_banned_until",
        ]
        until = _date_field(data, ban_until_keys)
        if banned and (until is None or until > datetime.now(timezone.utc)):
            return {
                "status": "policy_banned",
                "text": EDGE_POLICY_BAN_NOTICE,
                "banned_until": until.isoformat() if until else None,
            }
    except Exception as exc:
        print(f"AI_BAN_CHECK_FAILED user={user_id}: {exc}")
    return None


def _flag_policy_violation(
    user_id: str,
    reason: str,
    clip_index: int | None = None,
) -> dict[str, Any]:
    print(
        f"STRICT_POLICY_VIOLATION user={user_id} clip={clip_index} reason={reason}"
    )
    result: dict[str, Any] = {
        "count": 1,
        "text": STRICT_POLICY_NOTICE,
        "banned": False,
        "banned_until": None,
    }
    try:
        user_ref = _live_db().collection("users").document(user_id)
        snapshot = user_ref.get()
        data = snapshot.to_dict() or {}
        current_count = int(data.get("edge_policy_violation_count") or 0)
        next_count = current_count + 1
        update_data: dict[str, Any] = {
            "last_policy_flag": "non_cricket_edge_upload",
            "last_policy_flag_at": firestore.SERVER_TIMESTAMP,
            "edge_policy_violation_count": next_count,
        }
        if 7 <= next_count < 10:
            update_data["edge_policy_final_warning_count"] = next_count - 6
            result["text"] = FINAL_POLICY_WARNING_NOTICE
        elif next_count >= 10:
            banned_until = datetime.now(timezone.utc) + timedelta(days=27)
            update_data["edge_policy_banned_until"] = banned_until
            update_data["edge_policy_ban_reason"] = "repeated_non_cricket_edge_uploads"
            result["text"] = EDGE_POLICY_BAN_NOTICE
            result["banned"] = True
            result["banned_until"] = banned_until.isoformat()
        result["count"] = next_count
        user_ref.collection("policy_flags").add(
            {
                "type": "non_cricket_edge_upload",
                "reason": reason,
                "clip_index": clip_index,
                "violation_count": next_count,
                "created_at": firestore.SERVER_TIMESTAMP,
                "source": "cricknova_edge",
            }
        )
        user_ref.set(update_data, merge=True)
    except Exception as exc:
        print(f"STRICT_POLICY_FLAG_FAILED user={user_id}: {exc}")
    return result


def _debug_gemini_response(label: str, response: Any, model_name: str) -> None:
    print(f"===== {label} =====")
    print(f"MODEL: {model_name}")
    print("GEMINI RAW RESPONSE:")
    try:
        print(response)
    except Exception as exc:
        print(f"<raw response print failed: {exc}>")
    print("TEXT:")
    try:
        print(getattr(response, "text", None))
    except Exception as exc:
        print(f"<text read failed: {exc}>")
    print("CANDIDATES:")
    candidates = getattr(response, "candidates", None) or []
    print(candidates)
    for index, candidate in enumerate(candidates):
        print(f"CANDIDATE[{index}]: {candidate}")
        print(f"FINISH_REASON[{index}]: {getattr(candidate, 'finish_reason', None)}")
        print(f"SAFETY_RATINGS[{index}]: {getattr(candidate, 'safety_ratings', None)}")
        content = getattr(candidate, "content", None)
        if content:
            print(f"CONTENT[{index}]: {content}")
            print(f"PARTS[{index}]: {getattr(content, 'parts', None)}")
    print(f"===== END {label} =====")


def _live_edge_prompt(coach_name: str, language: str, discipline: str) -> str:
    spoken_name = _spoken_player_name(coach_name)
    coach_language = _normalize_live_language(language)
    role_rules = (
        "For batting, focus on stance, balance, footwork, bat path, timing, body alignment, and shot selection.\n"
        "For bowling, focus on run-up, body alignment, wrist position, seam presentation, release point, and follow-through."
    )
    return (
        "You are CrickNova Elite Coach.\n\n"
        "You are not a chatbot.\n\n"
        "You are a real professional cricket coach standing beside the player during practice.\n\n"
        "Speak naturally exactly like a human coach.\n\n"
        "Use the player's first name often.\n\n"
        "Never speak in fragments.\n\n"
        "Never reply with short generic praise or one-word feedback without explanation.\n\n"
        "Always explain WHY.\n\n"
        "Do not make the response revolve around one repeated body part.\n\n"
        "Analyze this cricket training clip.\n\n"
        "Critical cricket-only policy check:\n"
        "- First check whether this is a cricket-related video.\n"
        "- If it is not cricket-related, return exactly STRICT_POLICY_VIOLATION and nothing else.\n"
        "- If it is cricket-related, continue with coaching.\n\n"
        "Rules:\n"
        "- Only comment on visible actions.\n"
        "- Mention exactly:\n"
        "  1 positive observation.\n"
        "  1 biggest mistake.\n"
        "  1 immediate correction.\n"
        f"- Use the player's first name: {spoken_name}.\n"
        "- Be direct and realistic.\n"
        "- Avoid generic coaching phrases unless you explain the visible reason.\n\n"
        "Make coaching realistic.\n\n"
        f"{role_rules}\n\n"
        "Only comment on visible mechanics.\n\n"
        "Response must contain at least one complete coaching sentence.\n\n"
        "Sound:\n"
        "- Professional\n"
        "- Confident\n"
        "- Direct\n"
        "- Motivating\n\n"
        "Do not sound like AI.\n"
        "Do not sound like a commentator.\n"
        "Do not sound like a robot.\n\n"
        "Sound like a real academy coach training a player one-to-one.\n\n"
        f"Training mode: {discipline}.\n"
        f"Reply language: {coach_language}.\n"
        "Return natural coaching feedback as one flowing coach line."
    )


def _is_frame_too_dark(frame_bytes: bytes) -> bool:
    try:
        arr = np.frombuffer(frame_bytes, dtype=np.uint8)
        frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if frame is None:
            return True
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        mean_value = float(gray.mean())
        std_value = float(gray.std())
        bright_ratio = float(np.count_nonzero(gray > 35)) / float(gray.size)
        return mean_value < 22.0 or std_value < 10.0 or bright_ratio < 0.03
    except Exception:
        return False


def _video_has_visible_action(video_bytes: bytes) -> bool:
    frames = _sample_video_frames(video_bytes, max_frames=3)
    if not frames:
        return False
    visible = 0
    for frame in frames:
        if not _is_frame_too_dark(frame):
            visible += 1
    return visible >= 2


def _classify_active_cricket_action(frames: list[bytes]) -> str:
    usable_frames = [
        frame for frame in frames
        if isinstance(frame, (bytes, bytearray)) and not _is_frame_too_dark(frame)
    ][:3]
    if len(usable_frames) < 2:
        return "unknown"

    classifier_prompt = (
        "You are a visual pre-check for CrickNova Edge.\n"
        "Look only at the provided frames.\n"
        "Return exactly one label:\n"
        "ACTIVE_CRICKET_ACTION - if this looks cricket-related.\n"
        "STRICT_POLICY_VIOLATION - if this is clearly not cricket-related.\n"
        "If unsure, return ACTIVE_CRICKET_ACTION."
    )
    frame_parts = [
        types.Part.from_bytes(data=frame, mime_type="image/jpeg")
        for frame in usable_frames
    ]
    contents = _content_from_parts([
        _text_part_for_gemini(classifier_prompt),
        *frame_parts,
    ])

    def request_label(model_name: str) -> str:
        response = _generate_vision_content_with_key_rotation(
            model=model_name,
            contents=contents,
            config=types.GenerateContentConfig(
                temperature=0.0,
                max_output_tokens=12,
            ),
        )
        return " ".join(_extract_gemini_text(response).upper().split())

    for model_name in _vision_model_candidates()[:1]:
        executor = ThreadPoolExecutor(max_workers=1)
        try:
            label = executor.submit(request_label, model_name).result(timeout=8)
            print(f"CRICKET_ACTION_CLASSIFIER model={model_name} label={label}")
            if label == "STRICT_POLICY_VIOLATION":
                return "violation"
            if label == "ACTIVE_CRICKET_ACTION":
                return "active"
        except FutureTimeoutError:
            print(f"CRICKET_ACTION_CLASSIFIER_TIMEOUT model={model_name}")
            return "unknown"
        except Exception as exc:
            if _is_gemini_quota_error(exc):
                print(f"GEMINI_QUOTA_EXHAUSTED classifier model={model_name}: {exc}")
                continue
            print(f"CRICKET_ACTION_CLASSIFIER_FAILED model={model_name}: {exc}")
        finally:
            executor.shutdown(wait=False, cancel_futures=True)
    return "unknown"


def _classify_uploaded_cricket_video(video_path: str) -> str:
    try:
        with open(video_path, "rb") as video_file:
            video_bytes = video_file.read()
        if not _video_has_visible_action(video_bytes):
            print("UPLOAD_VIDEO_SKIPPED_TOO_DARK_OR_BLANK")
            return "violation"
    except Exception as exc:
        print(f"UPLOAD_VIDEO_LOCAL_VISIBILITY_CHECK_FAILED: {exc}")
        return "unknown"

    def request_video_label() -> str:
        client = _vision_gemini()
        uploaded_file = None
        try:
            uploaded_file = _upload_gemini_video_file(client, video_path)
            uploaded_file = _wait_for_gemini_file_active(
                client,
                uploaded_file,
                max_attempts=8,
            )
            classifier_prompt = (
                "Check this uploaded video only.\n"
                "Return exactly one label:\n"
                "ACTIVE_CRICKET_ACTION - if this is a cricket-related video.\n"
                "STRICT_POLICY_VIOLATION - if this is clearly not cricket-related.\n"
                "If unsure, return ACTIVE_CRICKET_ACTION."
            )
            contents = _content_from_parts([
                _file_part_for_gemini(uploaded_file),
                _text_part_for_gemini(classifier_prompt),
            ])
            response = _generate_vision_content_with_key_rotation(
                model=_vision_model_candidates()[0],
                contents=contents,
                config=types.GenerateContentConfig(
                    temperature=0.0,
                    max_output_tokens=12,
                ),
            )
            return " ".join(_extract_gemini_text(response).upper().split())
        finally:
            if uploaded_file is not None:
                _delete_gemini_file(client, uploaded_file)

    executor = ThreadPoolExecutor(max_workers=1)
    try:
        label = executor.submit(request_video_label).result(timeout=10)
        print(f"UPLOAD_CRICKET_VIDEO_CLASSIFIER label={label}")
        if label == "STRICT_POLICY_VIOLATION":
            return "violation"
        if label == "ACTIVE_CRICKET_ACTION":
            return "active"
        return "unknown"
    except FutureTimeoutError:
        print("UPLOAD_CRICKET_VIDEO_CLASSIFIER_TIMEOUT")
        return "unknown"
    except Exception as exc:
        if _is_gemini_quota_error(exc):
            print(f"GEMINI_QUOTA_EXHAUSTED upload_video_classifier: {exc}")
        else:
            print(f"UPLOAD_CRICKET_VIDEO_CLASSIFIER_FAILED: {exc}")
        return "unknown"
    finally:
        executor.shutdown(wait=False, cancel_futures=True)


def _non_cricket_upload_response(source: str) -> dict[str, Any]:
    return {
        "status": "non_cricket",
        "reason": "NO_CRICKET_ACTION",
        "message": UPLOAD_NON_CRICKET_NOTICE,
        "source": source,
    }


def _file_state_name(uploaded_file: Any) -> str:
    state = getattr(uploaded_file, "state", None)
    if state is None:
        return ""
    return str(getattr(state, "name", state)).upper()


def _upload_gemini_video_file(client: Client, video_path: str) -> Any:
    try:
        return client.files.upload(
            file=video_path,
            config=types.UploadFileConfig(mime_type="video/mp4"),
        )
    except Exception as first_exc:
        print(f"⚠️ Gemini file upload with config failed, retrying plain upload: {first_exc}")
        return client.files.upload(file=video_path)


def _wait_for_gemini_file_active(
    client: Client,
    uploaded_file: Any,
    *,
    max_attempts: int = 60,
) -> Any:
    name = getattr(uploaded_file, "name", None)
    current = uploaded_file
    for attempt in range(max_attempts):
        state_name = _file_state_name(current)
        uri = getattr(current, "uri", None)
        print(
            f"VIDEO_UPLOADED state={state_name or 'UNKNOWN'} "
            f"attempt={attempt} uri={uri or 'NO_URI'}"
        )
        if state_name in ("ACTIVE", "FILE_STATE_ACTIVE"):
            return current
        if state_name in ("FAILED", "FILE_STATE_FAILED"):
            raise RuntimeError(f"Gemini uploaded file failed processing: {current}")
        time.sleep(1)
        if name:
            current = client.files.get(name=name)
        elif uri and attempt >= 2:
            return current
    raise TimeoutError("Gemini uploaded video did not become ACTIVE in time")


def _file_part_for_gemini(uploaded_file: Any) -> Any:
    uri = getattr(uploaded_file, "uri", None)
    mime_type = getattr(uploaded_file, "mime_type", None) or "video/mp4"
    if uri and hasattr(types.Part, "from_uri"):
        return types.Part.from_uri(file_uri=uri, mime_type=mime_type)
    return uploaded_file


def _text_part_for_gemini(text: str) -> Any:
    if hasattr(types.Part, "from_text"):
        return types.Part.from_text(text=text)
    return text


def _content_from_parts(parts: list[Any]) -> list[Any]:
    try:
        return [types.Content(role="user", parts=parts)]
    except Exception:
        return parts


def _delete_gemini_file(client: Client, uploaded_file: Any) -> None:
    name = getattr(uploaded_file, "name", None)
    if not name:
        return
    with suppress(Exception):
        client.files.delete(name=name)


def _sample_video_frames(
    video_bytes: bytes,
    max_frames: int = 6,
    *,
    max_width: int | None = None,
    jpeg_quality: int = 88,
) -> list[bytes]:
    path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
            tmp.write(video_bytes)
            path = tmp.name

        cap = cv2.VideoCapture(path)
        if not cap.isOpened():
            print("⚠️ Could not open video clip for frame fallback")
            return []

        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        if frame_count <= 0:
            frame_count = max_frames
        indexes = sorted({
            min(frame_count - 1, max(0, round(i * (frame_count - 1) / max(1, max_frames - 1))))
            for i in range(max_frames)
        })

        sampled: list[bytes] = []
        for index in indexes:
            cap.set(cv2.CAP_PROP_POS_FRAMES, index)
            ok, frame = cap.read()
            if not ok or frame is None:
                continue
            if max_width and frame.shape[1] > max_width:
                scale = max_width / float(frame.shape[1])
                frame = cv2.resize(
                    frame,
                    (max_width, max(1, int(frame.shape[0] * scale))),
                    interpolation=cv2.INTER_AREA,
                )
            ok, encoded = cv2.imencode(
                ".jpg",
                frame,
                [int(cv2.IMWRITE_JPEG_QUALITY), int(jpeg_quality)],
            )
            if ok:
                sampled.append(encoded.tobytes())
        cap.release()
        print(f"🎞️ Extracted {len(sampled)} frames from live video fallback")
        return sampled
    except Exception as exc:
        print(f"❌ Video frame fallback failed: {exc}")
        return []
    finally:
        if path:
            with suppress(Exception):
                os.remove(path)


async def _analyze_live_frame(
    frame_bytes: bytes | list[bytes],
    *,
    coach_name: str = "Player",
    language: str = "English",
    discipline: str = "Batting",
    is_video: bool = False,
) -> tuple[str, str]:
    def run() -> str:
        prompt = _live_edge_prompt(coach_name, language, discipline)
        model_candidates = _vision_model_candidates()
        print(f"VIDEO_ANALYSIS_STARTED models={model_candidates} is_video={is_video}")
        try:
            client = _vision_gemini()

            if is_video and isinstance(frame_bytes, (bytes, bytearray)):
                video_path = None
                uploaded_file = None
                try:
                    if not _video_has_visible_action(bytes(frame_bytes)):
                        print("VIDEO_SKIPPED_TOO_DARK_OR_BLANK")
                        return "STRICT_POLICY_VIOLATION"
                    action_frames = _sample_video_frames(bytes(frame_bytes), max_frames=6)
                    action_label = _classify_active_cricket_action(action_frames)
                    if action_label == "violation":
                        print("VIDEO_SKIPPED_NON_CRICKET_ACTION")
                        return "STRICT_POLICY_VIOLATION"
                    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
                        tmp.write(bytes(frame_bytes))
                        video_path = tmp.name
                    print(f"VIDEO_RECEIVED bytes={len(frame_bytes)} path={video_path}")
                    uploaded_file = _upload_gemini_video_file(client, video_path)
                    print(f"VIDEO_UPLOADED file={uploaded_file}")
                    uploaded_file = _wait_for_gemini_file_active(client, uploaded_file)
                    file_part = _file_part_for_gemini(uploaded_file)
                    video_contents = _content_from_parts([
                        file_part,
                        _text_part_for_gemini(prompt),
                    ])

                    for model_name in model_candidates:
                        for attempt in range(2):
                            if attempt > 0:
                                print(f"GEMINI_RETRY video model={model_name}")
                            try:
                                response = _generate_vision_content_with_key_rotation(
                                    model=model_name,
                                    contents=video_contents,
                                    config=types.GenerateContentConfig(
                                        temperature=0.7,
                                        max_output_tokens=300,
                                    ),
                                )
                            except Exception as model_exc:
                                if _is_gemini_quota_error(model_exc):
                                    print(
                                        f"GEMINI_QUOTA_EXHAUSTED video model={model_name}: "
                                        f"{model_exc}"
                                    )
                                    break
                                raise
                            _debug_gemini_response(
                                "VIDEO_ANALYSIS_RESPONSE",
                                response,
                                model_name,
                            )
                            text = _extract_usable_gemini_text(response)
                            if text:
                                print(f"VIDEO_ANALYSIS_SUCCESS model={model_name} text={text}")
                                return text
                        print(f"GEMINI_EMPTY_RESPONSE video model={model_name}")
                except Exception as video_exc:
                    if _is_gemini_quota_error(video_exc):
                        print(f"GEMINI_QUOTA_EXHAUSTED video: {video_exc}")
                    print(f"❌ VIDEO_ANALYSIS_FAILED: {video_exc}")
                finally:
                    if uploaded_file is not None:
                        _delete_gemini_file(client, uploaded_file)
                    if video_path:
                        with suppress(Exception):
                            os.remove(video_path)

                print("FRAME_FALLBACK_STARTED")
                frames = _sample_video_frames(bytes(frame_bytes), max_frames=8)
                if frames:
                    frame_parts = [
                        types.Part.from_bytes(data=frame, mime_type="image/jpeg")
                        for frame in frames
                    ]
                    frame_contents = _content_from_parts([
                        _text_part_for_gemini(prompt),
                        *frame_parts,
                    ])
                    for model_name in model_candidates:
                        for attempt in range(2):
                            if attempt > 0:
                                print(f"GEMINI_RETRY frames model={model_name}")
                            try:
                                response = _generate_vision_content_with_key_rotation(
                                    model=model_name,
                                    contents=frame_contents,
                                    config=types.GenerateContentConfig(
                                        temperature=0.7,
                                        max_output_tokens=300,
                                    ),
                                )
                            except Exception as model_exc:
                                if _is_gemini_quota_error(model_exc):
                                    print(
                                        f"GEMINI_QUOTA_EXHAUSTED frames model={model_name}: "
                                        f"{model_exc}"
                                    )
                                    break
                                raise
                            _debug_gemini_response(
                                "FRAME_FALLBACK_RESPONSE",
                                response,
                                model_name,
                            )
                            text = _extract_usable_gemini_text(response)
                            if text:
                                print(f"FRAME_FALLBACK_SUCCESS model={model_name} text={text}")
                                return text
                        print(f"GEMINI_EMPTY_RESPONSE frames model={model_name}")
                print("GEMINI_EMPTY_RESPONSE frame_fallback")
                return ""

            frames = frame_bytes if isinstance(frame_bytes, list) else [frame_bytes]
            if frames and all(_is_frame_too_dark(frame) for frame in frames if isinstance(frame, (bytes, bytearray))):
                print("FRAME_SKIPPED_TOO_DARK_OR_BLANK")
                return ""
            frame_parts = [
                types.Part.from_bytes(data=frame, mime_type="image/jpeg")
                for frame in frames
            ]
            frame_contents = _content_from_parts([
                _text_part_for_gemini(prompt),
                *frame_parts,
            ])
            for model_name in model_candidates:
                for attempt in range(2):
                    if attempt > 0:
                        print(f"GEMINI_RETRY frames model={model_name}")
                    try:
                        response = _generate_vision_content_with_key_rotation(
                            model=model_name,
                            contents=frame_contents,
                            config=types.GenerateContentConfig(
                                temperature=0.7,
                                max_output_tokens=300,
                            ),
                        )
                    except Exception as model_exc:
                        if _is_gemini_quota_error(model_exc):
                            print(
                                f"GEMINI_QUOTA_EXHAUSTED frames model={model_name}: "
                                f"{model_exc}"
                            )
                            break
                        raise
                    _debug_gemini_response("FRAME_RESPONSE", response, model_name)
                    text = _extract_usable_gemini_text(response)
                    if text:
                        print(f"FRAME_FALLBACK_SUCCESS model={model_name} text={text}")
                        return text
                print(f"GEMINI_EMPTY_RESPONSE frames model={model_name}")
            print("GEMINI_EMPTY_RESPONSE frames")
            return ""
        except Exception as exc:
            if _is_gemini_quota_error(exc):
                print(f"GEMINI_QUOTA_EXHAUSTED model_candidates={model_candidates}: {exc}")
            print(f"❌ _analyze_live_frame FAILED: {exc}")
            return ""

    raw = await asyncio.to_thread(run)
    if raw == "STRICT_POLICY_VIOLATION":
        return "", "policy_violation"
    clean, mood = _clean_live_reply(raw)
    if not clean:
        print("GEMINI_NO_USABLE_REPLY returning_empty_text")
        return "", ""
    return clean, mood


@app.post("/live-nets/analyze-chunk/{user_id}")
async def analyze_live_nets_chunk(
    user_id: str,
    file: UploadFile = File(...),
    name: str = Form("Player"),
    language: str = Form("English"),
    discipline: str = Form("Batting"),
    clip_index: int = Form(0),
):
    try:
        banned_payload = _reject_if_edge_banned(user_id)
        if banned_payload is not None:
            banned_payload["clip_index"] = clip_index
            return banned_payload
        video_bytes = await file.read()
        print(
            f"🎬 HTTP live chunk user={user_id} clip={clip_index} "
            f"bytes={len(video_bytes)} lang={language} discipline={discipline}"
        )
        if not video_bytes:
            return {
                "status": "failed",
                "error": "EMPTY_VIDEO_CHUNK",
                "text": "",
                "mood": "",
                "clip_index": clip_index,
            }
        reply, mood = await _analyze_live_frame(
            video_bytes,
            coach_name=name,
            language=language,
            discipline=discipline,
            is_video=True,
        )
        if mood == "policy_violation":
            policy = _flag_policy_violation(
                user_id,
                "non_cricket_or_blank_edge_clip",
                clip_index,
            )
            return {
                "status": "policy_banned" if policy["banned"] else "policy_violation",
                "text": policy["text"],
                "mood": mood,
                "refund_minutes": False,
                "terminate_session": True,
                "clip_index": clip_index,
                "policy_violation_count": policy["count"],
                "banned_until": policy.get("banned_until"),
            }
        return {
            "status": "success" if reply else "empty",
            "text": reply,
            "mood": mood,
            "clip_index": clip_index,
        }
    except Exception as exc:
        import traceback
        print(f"❌ live chunk endpoint failed: {exc}")
        traceback.print_exc()
        return {
            "status": "failed",
            "error": str(exc),
            "text": "",
            "mood": "",
            "clip_index": clip_index,
        }


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


async def _live_from_flutter(
    client_ws: WebSocket,
    live_session: Any,
    stop: asyncio.Event,
    prompt_once: Any | None = None,
) -> None:
    async def send_video_frame(frame_bytes: bytes) -> None:
        blob = types.Blob(data=frame_bytes, mime_type="image/jpeg")
        sender = getattr(live_session, "send_realtime_input", None)
        if callable(sender):
            await sender(video=blob)
            return
        await live_session.send(input={"data": frame_bytes, "mime_type": "image/jpeg"})

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
                if callable(prompt_once):
                    await prompt_once()
            elif kind == "audio":
                audio = base64.b64decode(payload["data"])
                await live_session.send(input={"data": audio, "mime_type": "audio/pcm"})
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
            if callable(prompt_once):
                await prompt_once()


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


def _mark_task_failure(stop: asyncio.Event, task: asyncio.Task) -> None:
    if stop.is_set():
        return
    try:
        exc = task.exception()
    except asyncio.CancelledError:
        return
    except Exception:
        stop.set()
        return
    if exc is not None:
        stop.set()


@app.websocket("/ws/live-nets/{user_id}")
async def live_nets_socket(websocket: WebSocket, user_id: str) -> None:
    # Initialize stop event immediately to prevent UnboundLocalError in exception blocks
    stop = asyncio.Event()

    # Set SKIP_BILLING=true on Render to bypass balance check during testing
    SKIP_BILLING = os.getenv("SKIP_BILLING", "false").lower() in ("true", "1", "yes")
    # Default dev balance: 30 minutes
    DEV_BALANCE_MS = 30 * 60 * 1000
    starting_balance_ms = 0
    billed = False
    start_ns = time.monotonic_ns()

    try:
        await websocket.accept()
        ban_status = _edge_policy_ban_status(user_id)
        if ban_status is not None:
            await websocket.send_json(
                {
                    "type": "policy_banned",
                    "text": ban_status["text"],
                    "refund_minutes": False,
                    "terminate_session": True,
                    "banned_until": ban_status.get("banned_until"),
                }
            )
            await websocket.close(code=4003)
            return
        
        if SKIP_BILLING:
            starting_balance_ms = DEV_BALANCE_MS
            print(f"💰 User={user_id} using dev balance={starting_balance_ms}ms because SKIP_BILLING=true (Bypassing Firestore)")
        else:
            print(f"💰 User={user_id} fetching balance from Firestore...")
            try:
                starting_balance_ms = await _get_live_balance_ms(user_id)
                print(f"💰 User={user_id} balance={starting_balance_ms}ms from Firestore")
            except Exception as e:
                print(f"❌ Failed to query Firestore balance for user {user_id}: {e}")
                import traceback
                traceback.print_exc()
                await websocket.send_json({
                    "type": "error",
                    "reason": f"Firestore connection error: {e}"
                })
                await websocket.close(code=4003)
                return

        if starting_balance_ms <= 0:
            print("🚫 NO_LIVE_BALANCE — closing connection")
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

        await websocket.send_json(
            {
                "type": "connected",
                "model": _resolve_vision_model_name(),
            }
        )

        latest_frame: bytes | list[bytes] | None = None
        latest_is_video = False
        latest_clip_index: int | None = None
        analysis_event = asyncio.Event()
        analysis_running = False
        last_reply_at = 0.0
        coach_name = "Player"
        coach_language = "English"
        coach_discipline = "Batting"

        async def _analysis_loop() -> None:
            nonlocal latest_frame, latest_is_video, latest_clip_index, analysis_running, last_reply_at
            analysis_running = True
            print("🚀 _analysis_loop started")
            try:
                while not stop.is_set():
                    await analysis_event.wait()
                    analysis_event.clear()
                    print("📸 Frame received, sending to Gemini...")
                    while not stop.is_set() and latest_frame is not None:
                        frame = latest_frame
                        is_video = latest_is_video
                        clip_index = latest_clip_index
                        latest_frame = None
                        latest_is_video = False
                        latest_clip_index = None
                        try:
                            reply, mood = await _analyze_live_frame(
                                frame,
                                coach_name=coach_name,
                                language=coach_language,
                                discipline=coach_discipline,
                                is_video=is_video,
                            )
                        except Exception as exc:
                            print(f"❌ Analysis loop error: {exc}")
                            reply = ""
                            mood = "correction"
                        if reply:
                            print(f"📢 Sending transcript ({mood}): {reply}")
                            await websocket.send_json(
                                {
                                    "type": "transcript",
                                    "text": reply,
                                    "mood": mood,
                                    "clip_index": clip_index,
                                }
                            )
                            last_reply_at = time.monotonic()
                        elif mood == "policy_violation":
                            policy = _flag_policy_violation(
                                user_id,
                                "non_cricket_or_blank_edge_socket",
                                clip_index,
                            )
                            await websocket.send_json(
                                {
                                    "type": "policy_banned"
                                    if policy["banned"]
                                    else "policy_violation",
                                    "text": policy["text"],
                                    "refund_minutes": False,
                                    "clip_index": clip_index,
                                    "policy_violation_count": policy["count"],
                                    "banned_until": policy.get("banned_until"),
                                }
                            )
                            stop.set()
                            return
                        if latest_frame is None:
                            break
                        await asyncio.sleep(0.5)
            finally:
                analysis_running = False
                print("🛑 _analysis_loop ended")

        async def _receive_frames() -> None:
            nonlocal latest_frame, latest_is_video, latest_clip_index, coach_name, coach_language, coach_discipline
            print("🎥 _receive_frames started")
            try:
                while not stop.is_set():
                    message = await websocket.receive()
                    raw = message.get("bytes")
                    text = message.get("text")

                    if text is not None:
                        payload = json.loads(text)
                        kind = payload.get("type")
                        if kind == "client_config":
                            coach_name = str(payload.get("name", coach_name)).strip() or coach_name
                            coach_language = str(payload.get("language", coach_language)).strip() or coach_language
                            coach_discipline = str(payload.get("discipline", coach_discipline)).strip() or coach_discipline
                            print(f"⚙️ Config: name={coach_name} lang={coach_language} discipline={coach_discipline}")
                            continue
                        if kind == "video":
                            frame = base64.b64decode(payload["data"])
                            print(f"🎞️ Live frame received: {len(frame)} bytes")
                            # Accept frame if at least 0.5s since last reply
                            if (time.monotonic() - last_reply_at) >= 0.5:
                                latest_frame = frame
                                latest_is_video = False
                                latest_clip_index = None
                                analysis_event.set()
                        elif kind == "video_clip":
                            clip = base64.b64decode(payload["data"])
                            clip_index = payload.get("clip_index")
                            try:
                                clip_index = int(clip_index) if clip_index is not None else None
                            except (TypeError, ValueError):
                                clip_index = None
                            print(f"🎬 Live video #{clip_index} received: {len(clip)} bytes")
                            if clip and (time.monotonic() - last_reply_at) >= 0.5:
                                latest_frame = clip
                                latest_is_video = True
                                latest_clip_index = clip_index
                                analysis_event.set()
                        elif kind == "video_batch":
                            raw_frames = payload.get("frames") or []
                            frames = [
                                base64.b64decode(item)
                                for item in raw_frames
                                if isinstance(item, str) and item
                            ]
                            print(f"🎞️ Live frame batch received: {len(frames)} frames")
                            if frames and (time.monotonic() - last_reply_at) >= 0.5:
                                latest_frame = frames[-5:]
                                latest_is_video = False
                                latest_clip_index = None
                                analysis_event.set()
                        elif kind == "stop":
                            stop.set()
                            return
                        continue

                    if raw:
                        print(f"🎬 Live binary video received: {len(raw)} bytes")
                        if (time.monotonic() - last_reply_at) >= 0.5:
                            latest_frame = raw
                            latest_is_video = True
                            latest_clip_index = None
                            analysis_event.set()
            except WebSocketDisconnect:
                stop.set()

        tasks = [
            asyncio.create_task(
                _live_billing_guard(websocket, stop, start_ns, starting_balance_ms)
            ),
            asyncio.create_task(_analysis_loop()),
            asyncio.create_task(_receive_frames()),
        ]

        await stop.wait()
        for task in tasks:
            task.cancel()
        for task in tasks:
            with suppress(asyncio.CancelledError, WebSocketDisconnect):
                await task

        elapsed_ms = min(
            starting_balance_ms,
            (time.monotonic_ns() - start_ns) // 1_000_000,
        )
        if not SKIP_BILLING:
            try:
                await _charge_live_elapsed_ms(user_id, elapsed_ms)
                print(f"💰 Successfully charged user {user_id} for {elapsed_ms}ms")
            except Exception as e:
                print(f"❌ Failed to charge Firestore balance: {e}")
        else:
            print(f"ℹ️ SKIP_BILLING is true, bypassing Firestore charge of {elapsed_ms}ms")
        billed = True

    except WebSocketDisconnect:
        print(f"🔌 WebSocket disconnected for user {user_id}")
        with suppress(Exception):
            stop.set()
    except Exception as exc:
        print(f"❌ Exception in live_nets_socket: {exc}")
        import traceback
        traceback.print_exc()
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
        if not SKIP_BILLING and "starting_balance_ms" in locals() and "start_ns" in locals() and not billed:
            elapsed_ms = min(
                starting_balance_ms,
                (time.monotonic_ns() - start_ns) // 1_000_000,
            )
            with suppress(Exception):
                await _charge_live_elapsed_ms(user_id, elapsed_ms)


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

    turn_deg = raw_turn_deg

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
        ball_observations = track_ball_observations(video_path)
        ball_positions = [(float(item["x"]), float(item["y"])) for item in ball_observations]

        if len(ball_observations) < 5:
            return {
                "status": "failed",
                "reason": "Ball not detected clearly",
                "speed_kmph": None,
                "speed_confidence": 0.0,
                "swing": "unknown",
                "spin": "unknown",
                "trajectory": [],
                "model": "best-2.pt",
                "ball_point_count": len(ball_observations),
                "ball_points": [
                    {
                        "frame": int(item.get("frame", index)),
                        "x": round(float(item.get("x", 0.0)), 2),
                        "y": round(float(item.get("y", 0.0)), 2),
                        "confidence": float(item.get("confidence", 0.0)),
                        "interpolated": bool(item.get("interpolated", False)),
                    }
                    for index, item in enumerate(ball_observations)
                ],
            }

        cap = cv2.VideoCapture(video_path)
        frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        video_fps = cap.get(cv2.CAP_PROP_FPS)
        cap.release()

        if frame_width <= 0 or frame_height <= 0:
            frame_width, frame_height = 640, 360
        if video_fps is None or video_fps <= 1:
            video_fps = 30.0

        def robust_positive(values):
            clean = [float(v) for v in values if math.isfinite(float(v)) and float(v) > 0]
            if len(clean) < 3:
                return clean
            median = float(np.median(clean))
            mad = float(np.median([abs(v - median) for v in clean]))
            if mad <= 1e-9:
                return clean
            return [v for v in clean if abs(v - median) <= (3.5 * 1.4826 * mad)]

        def calculate_speed_kmph(observations, fps):
            if len(observations) < 5 or fps <= 1:
                return None

            ys = [float(p["y"]) for p in observations]
            pitch_idx = int(np.argmax(ys))
            usable = observations[: max(2, pitch_idx + 1)]

            if len(usable) < 3:
                return None

            px_per_frame = []
            confidence_samples = []
            for previous, current in zip(usable, usable[1:]):
                frame_gap = int(current["frame"]) - int(previous["frame"])
                if frame_gap <= 0:
                    continue
                distance_px = math.hypot(
                    float(current["x"]) - float(previous["x"]),
                    float(current["y"]) - float(previous["y"]),
                )
                if math.isfinite(distance_px) and distance_px > 0:
                    px_per_frame.append(distance_px / frame_gap)
                    confidence_samples.append(
                        min(
                            float(previous.get("confidence", 0.0)),
                            float(current.get("confidence", 0.0)),
                        )
                    )

            px_per_frame = robust_positive(px_per_frame)
            if not px_per_frame:
                return None

            pitch_span_px = float(np.percentile(ys, 95) - np.percentile(ys, 5))
            if pitch_span_px <= 1:
                return None

            meters_per_pixel = 20.12 / pitch_span_px
            speed_kmph = float(np.median(px_per_frame)) * float(fps) * meters_per_pixel * 3.6
            if speed_kmph <= 0 or not math.isfinite(speed_kmph):
                return None
            detection_confidence = float(np.mean(confidence_samples)) if confidence_samples else 0.0
            sample_confidence = min(len(px_per_frame) / 10.0, 1.0)
            speed_confidence = min(max(detection_confidence * 0.65 + sample_confidence * 0.35, 0.0), 1.0)
            return round(speed_kmph, 1), round(speed_confidence, 3)

        speed_result = calculate_speed_kmph(ball_observations, video_fps)
        speed_kmph = speed_result[0] if speed_result is not None else None
        speed_confidence = speed_result[1] if speed_result is not None else 0.0

        swing = detect_swing_x(ball_positions)
        spin_name, spin_turn = calculate_spin_real(ball_positions)
        trajectory = build_trajectory(ball_observations, frame_width, frame_height)

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
            "speed_type": "best_2_yolo_coordinate_physics",
            "speed_confidence": speed_confidence,
            "speed_note": "Speed from best-2.pt ball coordinates, real frame gaps, and pitch-length scale",
            "fps": round(float(video_fps), 3),
            "swing": swing,
            "spin": spin_label,
            "spin_strength": round(float(spin_turn), 3),
            "trajectory": trajectory,
            "model": "best-2.pt",
            "ball_point_count": len(ball_observations),
            "ball_points": [
                {
                    "frame": int(item["frame"]),
                    "x": round(float(item["x"]), 2),
                    "y": round(float(item["y"]), 2),
                    "confidence": float(item.get("confidence", 0.0)),
                    "interpolated": bool(item.get("interpolated", False)),
                }
                for item in ball_observations
            ],
        }

    finally:
        if os.path.exists(video_path):
            os.remove(video_path)




# -----------------------------
# AI COACH ANALYSIS API
# -----------------------------
@app.post("/coach/analyze")
async def ai_coach_analyze(request: Request, file: UploadFile = File(...)):
    if not _gemini_api_keys():
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")

    # ---- Subscription/Mistake Limit Check ----
    user_id = resolve_request_user_id(request, get_current_user(
        authorization=request.headers.get("Authorization")
    ))
    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")
    banned = _reject_if_any_ai_banned(user_id)
    if banned is not None:
        raise HTTPException(status_code=403, detail=banned["text"])

    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        tmp.write(await file.read())
        video_path = tmp.name

    try:
        from subscriptions_store import get_subscription, increment_mistake
        sub = get_subscription(user_id)
        try:
            increment_mistake(user_id)
        except Exception as e:
            print("⚠️ Mistake usage bypassed for active subscriber:", e)

        ball_positions = track_ball_positions(video_path)

        if not ball_positions or len(ball_positions) < 6:
            return {
                "status": "success",
                "coach_feedback": ""
            }

        swing = detect_swing_x(ball_positions)
        spin_name, _ = calculate_spin_real(ball_positions)

        prompt = """
You are CrickNova Coach.

Give short, honest batting feedback.
Mention one mistake and one improvement.
Focus on batting mechanics like stance, balance, bat path, timing, footwork, body alignment, and shot control.
Do not mention speed, swing, or spin.
"""

        feedback = generate_text(
            system_instruction="You are CrickNova Coach.",
            user_prompt=prompt,
            max_output_tokens=90,
            temperature=0.55,
        )

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
    history: list[dict] | None = None

@app.post("/coach/chat")
async def ai_coach_chat(request: Request, req: CoachChatRequest = Body(...)):
    if not _gemini_api_keys():
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")

    message = (req.message or "").strip()
    history = req.history or []

    if not message:
        return {
            "status": "success",
            "reply": "Ask me anything about batting, bowling, mindset, or match situations 🏏"
        }

    user_id = resolve_request_user_id(request, get_current_user(
        authorization=request.headers.get("Authorization")
    ))
    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")
    banned = _reject_if_any_ai_banned(user_id)
    if banned is not None:
        raise HTTPException(status_code=403, detail=banned["text"])

    from subscriptions_store import get_subscription, increment_chat
    sub = get_subscription(user_id)
    try:
        increment_chat(user_id)
    except Exception as e:
        print("⚠️ Chat usage bypassed for active subscriber:", e)
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
            or "strict instructions" in msg_lower
            or "output structure" in msg_lower
            or "user mistake" in msg_lower
            or "coaching task" in msg_lower
            or "[mistakes]" in msg_lower
            or "[how to fix]" in msg_lower
            or "[drill]" in msg_lower
        )
        if looks_like_raw_prompt:
            reply_text = generate_text(
                system_instruction=(
                    "You are CrickNova batting coach. "
                    "Analyze only the provided clip context. "
                    "Be direct, honest, and unscripted. "
                    "Avoid repeated generic lines."
                ),
                user_prompt=message,
                max_output_tokens=320,
                temperature=0.72,
            )
            return {"status": "success", "reply": reply_text}

        history_lines = []
        for item in history[-8:]:
            if not isinstance(item, dict):
                continue
            role = str(item.get("role", "user")).strip().lower()
            content = str(item.get("content", "")).strip()
            if not content:
                continue
            prefix = "User" if role == "user" else "Coach"
            history_lines.append(f"{prefix}: {content}")

        history_block = "\n".join(history_lines).strip()

        prompt = f'''
You are CrickNova Coach, a real cricket coach powered by CrickNova AI.

Answer the user's actual question in natural coaching language.
Do not use a fixed 4-point template unless the user explicitly asks for points.
Do not sound scripted, repetitive, or generic.

Rules:
- Answer every cricket-related question.
- If the question is vague, ask 1 short follow-up or give neutral cricket guidance.
- Keep the answer direct, practical, and human.
- No fake video analysis if no clip context is provided.
- No unnecessary headings unless they help the answer.
- Keep the answer concise, but answer the exact question asked.
- Use the recent chat history only to maintain continuity for follow-up questions like "give tips", "why", or "what next".
- If the new question changes topic, answer the new topic directly.

Recent chat history:
{history_block if history_block else "No previous chat context."}

User question:
{message}
'''

        reply_text = generate_text(
            system_instruction="You are CrickNova Coach.",
            user_prompt=prompt,
            max_output_tokens=220,
            temperature=0.72,
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
):
    if not _gemini_api_keys():
        raise HTTPException(status_code=503, detail="AI_TEMPORARILY_UNAVAILABLE")

    # ---- Subscription/Compare Limit Check ----
    user_id = resolve_request_user_id(request, get_current_user(
        authorization=request.headers.get("Authorization")
    ))
    if not user_id:
        raise HTTPException(status_code=401, detail="USER_NOT_AUTHENTICATED")
    banned = _reject_if_any_ai_banned(user_id)
    if banned is not None:
        raise HTTPException(status_code=403, detail=banned["text"])

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
        from subscriptions_store import get_subscription, increment_compare
        sub = get_subscription(user_id)
        try:
            increment_compare(user_id)
        except Exception as e:
            print("⚠️ Compare usage bypassed for active subscriber:", e)

        try:
            left_positions = track_ball_positions(left_path) or []
        except Exception:
            left_positions = []
        try:
            right_positions = track_ball_positions(right_path) or []
        except Exception:
            right_positions = []

        base_prompt = (prompt or "").strip()
        if not base_prompt:
            base_prompt = """
You are CrickNova Coach.

Compare the player's two videos honestly in natural coaching language.
Do not force Video 2 to be better than Video 1.
No fixed template or forced headings.
Explain what improved, what is still weak, and what to do next.
Give exactly 2 practical drills.
- Do not mention speed, swing, or spin.
- Keep it specific to what changed between the two clips.
Do not give rating/score.
Keep the full reply under 260 words and avoid generic wording.
"""

        final_prompt = (
            base_prompt
            + f"\n\nINTERNAL_CONTEXT (do not mention): "
              f"v1_name={(left.filename or 'left.mp4')} "
              f"v2_name={(right.filename or 'right.mp4')} "
              f"v1_sig={trajectory_signature(left_positions)} "
              f"v2_sig={trajectory_signature(right_positions)}\n"
        )

        diff_text = generate_text(
            system_instruction=(
                "You are CrickNova batting coach. "
                "Give batting-only comparison and batting drills only. "
                "Never provide bowling analysis. "
                "Make the response clip-specific and avoid repeating generic lines."
            ),
            user_prompt=final_prompt,
            max_output_tokens=260,
            temperature=0.6,
        )

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
