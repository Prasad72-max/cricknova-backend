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

def extract_video_keyframes(video_path: str, max_frames: int = 3) -> list[bytes]:
    """⚡ Pure FFmpeg video keyframe extractor — 100% OpenCV-free (Only NVIDIA vision model used)."""
    frames: list[bytes] = []
    if not os.path.exists(video_path):
        return frames

    import subprocess
    import tempfile
    import shutil

    ffmpeg_bin = (
        shutil.which("ffmpeg")
        or ("/opt/homebrew/bin/ffmpeg" if os.path.exists("/opt/homebrew/bin/ffmpeg") else None)
        or ("/usr/bin/ffmpeg" if os.path.exists("/usr/bin/ffmpeg") else "ffmpeg")
    )
    try:
        with tempfile.TemporaryDirectory() as tmp_dir:
            cmd = [
                ffmpeg_bin, "-v", "error", "-y", "-i", video_path,
                "-vf", "fps=1.5,scale=360:-2",
                "-q:v", "4",
                "-vframes", str(max_frames),
                os.path.join(tmp_dir, "frame_%02d.jpg")
            ]
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4)
            for f in sorted(os.listdir(tmp_dir)):
                if f.endswith(".jpg"):
                    with open(os.path.join(tmp_dir, f), "rb") as fp:
                        b = fp.read()
                        if b:
                            frames.append(b)
    except Exception as e:
        print("⚠️ Pure FFmpeg extraction notice:", e)

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
    system_instruction: str = "You are a universal cricket coach. Keep your responses focused on cricket.",
    model: str | None = None,
    max_output_tokens: int = 4096,
    temperature: float = 0.35,
) -> str:
    """⚡ Two-video comparison using NVIDIA Nemotron 3.5 Super VL multimodal vision."""
    content_parts: list[dict[str, Any]] = [
        {
            "type": "text",
            "text": (
                "You are evaluating two cricket video clips. The first attached frames are Video 1 and the second attached frames are Video 2.\n\n"
                f"{prompt}\n\n"
            )
        }
    ]

    if not left_frames and left_video_bytes:
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
            tmp.write(left_video_bytes)
            tmp_path = tmp.name
        try:
            left_frames = extract_video_keyframes(tmp_path, max_frames=3)
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    if not right_frames and right_video_bytes:
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
            tmp.write(right_video_bytes)
            tmp_path = tmp.name
        try:
            right_frames = extract_video_keyframes(tmp_path, max_frames=3)
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    if left_frames and right_frames:
        for title, f_list in (("VIDEO 1", left_frames), ("VIDEO 2", right_frames)):
            content_parts.append({"type": "text", "text": f"{title} frames:"})
            for frame in f_list[:3]:
                encoded = base64.b64encode(frame).decode("ascii")
                content_parts.append({
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{encoded}"},
                })

    content_parts.append({
        "type": "text",
        "text": (
            "Carefully analyze the cricket technique across both videos.\n"
            "Strictly follow the requested format with [VIDEO 1: Technique and mistakes in Clip 1] and [VIDEO 2: Technique differences and improvement] sections."
        )
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
        print(f"⚠️ Comparison vision failed: {e}. Falling back to text.")
        return generate_nvidia_text(
            system_instruction=system_instruction,
            user_prompt=prompt,
            model=model or NVIDIA_MODEL,
            max_output_tokens=max_output_tokens,
            temperature=temperature,
        )
