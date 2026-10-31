import os
import re
import json
import base64
import http.client
import socket
import ssl
import threading
from typing import Any
# ⚡ Load environment variables (with fallback manual parser if dotenv not installed)
try:
    from dotenv import load_dotenv
    load_dotenv()
    _backend_env = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if os.path.exists(_backend_env):
        load_dotenv(_backend_env)
    _cricknova_backend_env = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cricknova_ai_backend", ".env")
    if os.path.exists(_cricknova_backend_env):
        load_dotenv(_cricknova_backend_env)
except ImportError:
    pass

def _load_env_file_fallback(path: str):
    if not os.path.exists(path):
        return
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip("'\"")
                if k and k not in os.environ:
                    os.environ[k] = v
    except Exception:
        pass

_load_env_file_fallback(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))
_load_env_file_fallback(os.path.join(os.path.dirname(os.path.abspath(__file__)), "cricknova_ai_backend", ".env"))

# ⚡ Dynamically import NVIDIA AI Model from environment variables
NVIDIA_MODEL = (
    os.getenv("NVIDIA_MODEL")
    or os.getenv("NVIDIA_AI_MODEL")
    or os.getenv("NV_MODEL")
    or os.getenv("MISTAKE_MODEL")
    or os.getenv("MISTAKE_DETECTION_MODEL")
    or os.getenv("AI_MODEL")
    or "nvidia/nemotron-3.5-super-vl-120b-a12b"
)
NVIDIA_HOST = os.getenv("NVIDIA_HOST", "integrate.api.nvidia.com")
NVIDIA_PATH = os.getenv("NVIDIA_PATH", "/v1/chat/completions")

# ⚡ High-speed connection reuse (Keep-Alive pool)
_conn_lock = threading.Lock()
_cached_conn: http.client.HTTPSConnection | None = None
_ssl_ctx = ssl.create_default_context()

def _get_connection(timeout: int = 25) -> http.client.HTTPSConnection:
    global _cached_conn
    with _conn_lock:
        if _cached_conn is None:
            _cached_conn = http.client.HTTPSConnection(
                NVIDIA_HOST,
                context=_ssl_ctx,
                timeout=timeout,
            )
        return _cached_conn

def _reset_connection():
    global _cached_conn
    with _conn_lock:
        if _cached_conn is not None:
            try:
                _cached_conn.close()
            except Exception:
                pass
            _cached_conn = None

def get_nvidia_api_keys() -> list[str]:
    keys: list[str] = []
    candidates = [
        "NVIDIA_API_KEY",
        "NV_API_KEY",
        "NVIDIA_KEY",
        "MARK_AI_API_KEY",
        "MARK_AI_KEY",
        "NVIDIA_API_KEYS",
    ]
    for env_name in candidates:
        val = (os.getenv(env_name) or "").strip()
        if not val:
            continue
        for item in re.split(r"[,\s]+", val):
            k = item.strip()
            if k and k not in keys:
                keys.append(k)

    for index in range(1, 11):
        for prefix in ("NVIDIA_API_KEY_", "NV_KEY_", "NVIDIA_KEY_"):
            val = (os.getenv(f"{prefix}{index}") or "").strip()
            if val and val not in keys:
                keys.append(val)
    return keys

def get_primary_nvidia_key() -> str | None:
    keys = get_nvidia_api_keys()
    for k in keys:
        if k.startswith("nvapi-"):
            return k
    return keys[0] if keys else None

def is_nvidia_available() -> bool:
    return len(get_nvidia_api_keys()) > 0

def call_nvidia_chat(
    messages: list[dict[str, Any]],
    *,
    model: str | None = None,
    max_tokens: int = 4096,
    temperature: float = 0.55,
    timeout: int = 50,
) -> str:
    """⚡ NVIDIA AI API caller with 4,096 token limit & fast Keep-Alive connection pooling."""
    keys = get_nvidia_api_keys()
    if not keys:
        raise RuntimeError("NVIDIA_API_KEY is not set in environment variables")

    target_model = (model or NVIDIA_MODEL).strip()
    payload = {
        "model": target_model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    body = json.dumps(payload).encode("utf-8")
    last_err: Exception | None = None

    for key in keys:
        headers = {
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Connection": "keep-alive",
            "User-Agent": "CrickNova-Fast/1.0",
        }

        # Attempt 1: Fast Keep-Alive connection
        for attempt in range(2):
            try:
                conn = _get_connection(timeout=timeout)
                conn.request("POST", NVIDIA_PATH, body=body, headers=headers)
                resp = conn.getresponse()
                raw_bytes = resp.read()

                if resp.status == 200:
                    resp_data = json.loads(raw_bytes.decode("utf-8"))
                    choices = resp_data.get("choices") or []
                    if choices:
                        content = choices[0].get("message", {}).get("content", "")
                        return content.strip()
                    return ""
                elif resp.status in (401, 403, 429, 500):
                    _reset_connection()
                    print(f"⚠️ NVIDIA Key returned {resp.status}, trying next key")
                    last_err = RuntimeError(f"NVIDIA API {resp.status}: {raw_bytes.decode('utf-8', 'ignore')}")
                    break
                else:
                    _reset_connection()
                    last_err = RuntimeError(f"NVIDIA API Error {resp.status}: {raw_bytes.decode('utf-8', 'ignore')}")
            except Exception as e:
                _reset_connection()
                last_err = e
                if isinstance(e, (TimeoutError, socket.timeout)):
                    raise RuntimeError("NVIDIA API request timed out") from e
                if attempt == 0:
                    continue
                break

    raise RuntimeError(f"All NVIDIA API attempts failed: {last_err}")

def generate_nvidia_text(
    *,
    system_instruction: str = "You are CrickNova Coach.",
    user_prompt: str,
    model: str | None = None,
    max_output_tokens: int = 4096,
    temperature: float = 0.55,
) -> str:
    """⚡ Complete & accurate text generation using NVIDIA Nemotron 3.5 Super VL."""
    messages = [
        {"role": "system", "content": system_instruction},
        {"role": "user", "content": user_prompt},
    ]
    return call_nvidia_chat(
        messages,
        model=model or NVIDIA_MODEL,
        max_tokens=max_output_tokens,
        temperature=temperature,
    )

def extract_video_keyframes(video_path: str, max_frames: int = 2) -> list[bytes]:
    """⚡ Ultra-fast (<0.1s) keyframe extraction for NVIDIA vision using FFmpeg input-seeking & cv2."""
    frames: list[bytes] = []
    if not os.path.exists(video_path) or os.path.getsize(video_path) == 0:
        return frames

    # Find FFmpeg binary: imageio_ffmpeg bundled static binary > PATH > standard paths
    ffmpeg_bin = None
    try:
        import imageio_ffmpeg
        ffmpeg_bin = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        pass

    if not ffmpeg_bin:
        import shutil
        ffmpeg_bin = (
            shutil.which("ffmpeg")
            or ("/opt/homebrew/bin/ffmpeg" if os.path.exists("/opt/homebrew/bin/ffmpeg") else None)
            or ("/usr/bin/ffmpeg" if os.path.exists("/usr/bin/ffmpeg") else None)
        )

    # Strategy 1: Ultra-fast input-seeking FFmpeg (-ss before -i takes <0.05s)
    if ffmpeg_bin:
        import subprocess
        import tempfile
        timestamps = ["0.5", "1.5"] if max_frames == 2 else ["0.3", "1.0", "1.8"]
        try:
            with tempfile.TemporaryDirectory() as tmp_dir:
                for i, ts in enumerate(timestamps[:max_frames]):
                    out_path = os.path.join(tmp_dir, f"f_{i}.jpg")
                    cmd = [
                        ffmpeg_bin, "-ss", ts, "-i", video_path,
                        "-vf", "scale=360:-2",
                        "-vframes", "1",
                        "-q:v", "6",
                        "-y", out_path
                    ]
                    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4)
                    if os.path.exists(out_path) and os.path.getsize(out_path) > 0:
                        with open(out_path, "rb") as fp:
                            frames.append(fp.read())
            if frames:
                return frames
        except Exception as exc:
            print("Fast FFmpeg extract notice:", exc)

    # Strategy 2: Sequential cv2 frame grab (never seek with CAP_PROP_POS_FRAMES)
    try:
        import cv2
        cap = cv2.VideoCapture(video_path)
        if cap.isOpened():
            count = 0
            while len(frames) < max_frames and count < 60:
                ret, frame = cap.read()
                if not ret or frame is None:
                    break
                if count in (5, 25, 45) or (count == 0 and len(frames) == 0):
                    h, w = frame.shape[:2]
                    target_w = 360
                    target_h = max(180, int(h * (360.0 / max(1, w))))
                    resized = cv2.resize(frame, (target_w, target_h), interpolation=cv2.INTER_AREA)
                    success, buf = cv2.imencode(".jpg", resized, [int(cv2.IMWRITE_JPEG_QUALITY), 65])
                    if success and buf is not None:
                        frames.append(buf.tobytes())
                count += 1
            cap.release()
            if frames:
                return frames
    except Exception as exc:
        print("Sequential cv2 extract notice:", exc)

    return frames

def generate_nvidia_vision(
    *,
    prompt: str,
    frames: list[bytes] | None = None,
    video_bytes: bytes | None = None,
    video_mime_type: str = "video/mp4",
    system_instruction: str = "You are a universal cricket coach. Keep your responses focused on cricket.",
    model: str | None = None,
    max_output_tokens: int = 4096,
    temperature: float = 0.35,
) -> str:
    """⚡ Rapid multimodal analysis using NVIDIA Nemotron 3.5 Super VL."""
    content_parts: list[dict[str, Any]] = [
        {"type": "text", "text": prompt}
    ]

    # If frames not provided directly, extract clean 480p keyframes from video_bytes
    if (not frames or len(frames) == 0) and video_bytes:
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
            tmp.write(video_bytes)
            tmp_path = tmp.name
        try:
            frames = extract_video_keyframes(tmp_path, max_frames=4)
        finally:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except Exception:
                    pass

    if frames and len(frames) > 0:
        step = max(1, len(frames) // 4)
        sampled = frames[::step][:4]
        for f in sampled:
            b64_img = base64.b64encode(f).decode("utf-8")
            content_parts.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{b64_img}"}
            })
    messages = [
        {"role": "system", "content": system_instruction},
        {"role": "user", "content": content_parts},
    ]

    try:
        return call_nvidia_chat(
            messages,
            model=model or NVIDIA_MODEL,
            max_tokens=max_output_tokens,
            temperature=temperature,
            timeout=50,
        )
    except Exception as e:
        print(f"⚠️ NVIDIA Vision failed: {e}. Falling back to fast text completion...")
        return generate_nvidia_text(
            system_instruction=system_instruction,
            user_prompt=prompt,
            model=model or NVIDIA_MODEL,
            max_output_tokens=max_output_tokens,
            temperature=temperature,
        )

def generate_nvidia_comparison_vision(
    *,
    prompt: str,
    discipline: str = "cricket",
    left_video_bytes: bytes | None = None,
    right_video_bytes: bytes | None = None,
    left_frames: list[bytes] | None = None,
    right_frames: list[bytes] | None = None,
    left_video_mime_type: str = "video/mp4",
    right_video_mime_type: str = "video/mp4",
    system_instruction: str = "You are a professional cricket coach. Keep your responses focused on cricket.",
    model: str | None = None,
    max_output_tokens: int = 4096,
    temperature: float = 0.35,
) -> str:
    """⚡ Two-video comparison using NVIDIA Nemotron 3.5 Super VL multimodal vision."""
    if not left_frames and left_video_bytes:
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
            tmp.write(left_video_bytes)
            tmp_path = tmp.name
        try:
            left_frames = extract_video_keyframes(tmp_path, max_frames=2)
        finally:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except Exception:
                    pass

    if not right_frames and right_video_bytes:
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
            tmp.write(right_video_bytes)
            tmp_path = tmp.name
        try:
            right_frames = extract_video_keyframes(tmp_path, max_frames=2)
        finally:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except Exception:
                    pass

    content_parts: list[dict[str, Any]] = [
        {
            "type": "text",
            "text": (
                f"You are a professional, India-level cricket {discipline} coach evaluating two cricket action clips.\n"
                f"Below are the visual frames extracted from Video 1 and Video 2.\n\n"
                f"{prompt}"
            )
        }
    ]

    if left_frames:
        content_parts.append({"type": "text", "text": "=== VIDEO 1 FRAMES ==="})
        for frame in left_frames[:2]:
            encoded = base64.b64encode(frame).decode("ascii")
            content_parts.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{encoded}"},
            })

    if right_frames:
        content_parts.append({"type": "text", "text": "=== VIDEO 2 FRAMES ==="})
        for frame in right_frames[:2]:
            encoded = base64.b64encode(frame).decode("ascii")
            content_parts.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{encoded}"},
            })

    messages = [
        {"role": "system", "content": system_instruction},
        {"role": "user", "content": content_parts},
    ]

    try:
        return call_nvidia_chat(
            messages,
            model=model or NVIDIA_MODEL,
            max_tokens=max_output_tokens,
            temperature=temperature,
            timeout=25,
        )
    except Exception as e:
        print(f"⚠️ Comparison vision call failed: {e}. Falling back to text.")
        fallback_prompt = (
            f"You are a professional, India-level cricket {discipline} coach.\n"
            f"Provide a direct technical comparison between Video 1 and Video 2 focusing on body alignment, timing, bat path/bowling arm, and follow-through.\n"
            f"Return strictly the requested 4 comparison points and Final Verdict:\n\n"
            f"{prompt}"
        )
        return generate_nvidia_text(
            system_instruction=system_instruction,
            user_prompt=fallback_prompt,
            model=model or NVIDIA_MODEL,
            max_output_tokens=max_output_tokens,
            temperature=temperature,
        )
