import os
import re
import json
import base64
import http.client
import socket
import ssl
import threading
from typing import Any

NVIDIA_MODEL = "nvidia/nemotron-3.5-super-vl-120b-a12b"
NVIDIA_HOST = "integrate.api.nvidia.com"
NVIDIA_PATH = "/v1/chat/completions"

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
    model: str = NVIDIA_MODEL,
    max_tokens: int = 8192,
    temperature: float = 0.55,
    timeout: int = 50,
) -> str:
    """⚡ NVIDIA Nemotron API caller with 8K+ token capacity & Keep-Alive connection pooling."""
    keys = get_nvidia_api_keys()
    if not keys:
        raise RuntimeError("NVIDIA_API_KEY is not set in environment variables")

    payload = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    if any(
        isinstance(message.get("content"), list)
        and any(part.get("type") == "video_url" for part in message["content"] if isinstance(part, dict))
        for message in messages
    ):
        payload["media_io_kwargs"] = {"video": {"num_frames": 16, "fps": -1}}
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
                elif resp.status in (401, 403, 429):
                    _reset_connection()
                    print(f"⚠️ NVIDIA Key {resp.status}, trying next key")
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
    max_output_tokens: int = 8192,
    temperature: float = 0.55,
) -> str:
    """⚡ Complete & accurate text generation using NVIDIA Nemotron 3.5 Super VL."""
    messages = [
        {"role": "system", "content": system_instruction},
        {"role": "user", "content": user_prompt},
    ]
    return call_nvidia_chat(
        messages,
        max_tokens=max_output_tokens,
        temperature=temperature,
    )

def extract_video_keyframes(video_path: str, max_frames: int = 4) -> list[bytes]:
    """⚡ High-speed keyframe extractor using OpenCV with FFmpeg fallback."""
    frames: list[bytes] = []
    if not os.path.exists(video_path):
        return frames

    # 1. Try OpenCV
    try:
        import cv2
        cap = cv2.VideoCapture(video_path)
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        if total > 0:
            count = min(max_frames, total)
            positions = [int(total * (i + 1) / (count + 1)) for i in range(count)]
            for pos in positions:
                cap.set(cv2.CAP_PROP_POS_FRAMES, pos)
                ret, fr = cap.read()
                if ret and fr is not None:
                    h, w = fr.shape[:2]
                    if w > 480:
                        new_w = 480
                        new_h = int(h * (480 / w))
                        fr = cv2.resize(fr, (new_w, new_h))
                    _, buf = cv2.imencode(".jpg", fr, [int(cv2.IMWRITE_JPEG_QUALITY), 60])
                    frames.append(buf.tobytes())
        cap.release()
    except Exception as e:
        print("⚠️ OpenCV extraction notice:", e)

    # 2. Try FFmpeg fallback if OpenCV extracted nothing
    if not frames:
        import subprocess
        import tempfile
        ffmpeg_bin = "/opt/homebrew/bin/ffmpeg" if os.path.exists("/opt/homebrew/bin/ffmpeg") else "ffmpeg"
        try:
            with tempfile.TemporaryDirectory() as tmp_dir:
                cmd = [
                    ffmpeg_bin, "-v", "error", "-y", "-i", video_path,
                    "-vf", "fps=1,scale=min(640\\,iw):-2",
                    "-q:v", "3", "-vframes", str(max_frames),
                    os.path.join(tmp_dir, "frame_%02d.jpg")
                ]
                subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
                for f in sorted(os.listdir(tmp_dir)):
                    if f.endswith(".jpg"):
                        with open(os.path.join(tmp_dir, f), "rb") as fp:
                            frames.append(fp.read())
        except Exception as e:
            print("⚠️ FFmpeg fallback notice:", e)

    return frames

def generate_nvidia_vision(
    *,
    prompt: str,
    frames: list[bytes] | None = None,
    video_bytes: bytes | None = None,
    video_mime_type: str = "video/mp4",
    system_instruction: str = "You are a universal cricket coach. Keep your responses focused on cricket.",
    max_output_tokens: int = 8192,
    temperature: float = 0.55,
) -> str:
    """⚡ Rapid multimodal analysis using NVIDIA Nemotron 3.5 Super VL."""
    content_parts: list[dict[str, Any]] = [
        {"type": "text", "text": prompt}
    ]

    if video_bytes:
        content_parts.append({
            "type": "video_url",
            "video_url": {
                "url": f"data:{video_mime_type};base64,{base64.b64encode(video_bytes).decode('ascii')}"
            },
        })
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

    return call_nvidia_chat(
        messages,
        max_tokens=max_output_tokens,
        temperature=temperature,
        timeout=50,
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
    max_output_tokens: int = 8192,
    temperature: float = 0.55,
) -> str:
    """⚡ Two-video comparison using NVIDIA Nemotron 3.5 Super VL multimodal vision."""
    content_parts: list[dict[str, Any]] = [
        {
            "type": "text",
            "text": (
                "You are evaluating two cricket video clips. The first attached video is Video 1 and the second attached video is Video 2.\n\n"
                f"{prompt}\n\n"
            )
        }
    ]

    if left_video_bytes and right_video_bytes:
        for video_bytes, mime_type in (
            (left_video_bytes, left_video_mime_type),
            (right_video_bytes, right_video_mime_type),
        ):
            content_parts.append({
                "type": "video_url",
                "video_url": {
                    "url": f"data:{mime_type};base64,{base64.b64encode(video_bytes).decode('ascii')}"
                },
            })
    elif left_frames and right_frames:
        for title, frames in (("VIDEO 1", left_frames), ("VIDEO 2", right_frames)):
            content_parts.append({"type": "text", "text": f"{title} frames"})
            for frame in frames[:4]:
                encoded = base64.b64encode(frame).decode("ascii")
                content_parts.append({
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{encoded}"},
                })
    else:
        raise ValueError("Provide both videos or both frame lists for comparison")

    normalized_discipline = discipline.strip().lower()
    if normalized_discipline == "batting":
        technique_focus = (
            "Evaluate batting technique only: set-up and stance, head position, balance, footwork, weight transfer, "
            "bat swing/path, contact and timing, shot control, and follow-through."
        )
    elif normalized_discipline == "bowling":
        technique_focus = (
            "Evaluate bowling technique only: run-up rhythm, gather, front-foot landing, alignment, balance, "
            "bowling-arm path, release position, follow-through, and visible line/length outcome."
        )
    else:
        technique_focus = "Identify the requested cricket skill and compare its visible technique only."

    content_parts.append({
        "type": "text",
        "text": (
            f"{technique_focus}\n"
            "This is a TECHNIQUE COMPARISON, not a scene caption. Ignore clothing, clothing color, player appearance, grass, nets, venue, camera angle, and background unless they prevent technique from being seen. Do not spend either section describing those details.\n"
            "Confirm that the requested cricket skill is visible in both clips. If either clip is not cricket or does not show the requested skill, use the two sections to say technique cannot be compared and briefly identify only the relevant visibility problem. Do not invent mistakes for a non-cricket clip.\n"
            "For valid clips, return exactly these two sections:\n"
            "[VIDEO 1: Technique and mistakes in Clip 1]\nUse labelled lines: What needs work: a visible technique mistake and its movement evidence. What worked: only a strength supported by the clip. Key note: relevant technique evidence. If no clear mistake is visible, state that instead of inventing one.\n"
            "[VIDEO 2: Technique differences and improvement]\nUse labelled lines: Difference: compare the same technique point in Clip 1 and Clip 2 with evidence from both. What worked: a visible improvement. What needs work: a mistake that remains or worsens and one specific correction. Do not assume Clip 2 is better.\n"
            "Base every claim only on the supplied video evidence. Do not infer unseen body positions or actions. If details cannot be established from the frames, state that briefly."
        )
    })

    messages = [
        {"role": "system", "content": system_instruction},
        {"role": "user", "content": content_parts},
    ]

    return call_nvidia_chat(
        messages,
        max_tokens=max_output_tokens,
        temperature=temperature,
        timeout=50,
    )
