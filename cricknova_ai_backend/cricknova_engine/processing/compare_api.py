from fastapi import APIRouter, UploadFile, File, Form
import tempfile
import os
from concurrent.futures import ThreadPoolExecutor

try:
    from nvidia_client import (
        is_nvidia_available,
        extract_video_keyframes,
        generate_nvidia_comparison_vision,
        generate_nvidia_text,
        NVIDIA_MODEL
    )
except ImportError:
    from cricknova_ai_backend.nvidia_client import (
        is_nvidia_available,
        extract_video_keyframes,
        generate_nvidia_comparison_vision,
        generate_nvidia_text,
        NVIDIA_MODEL
    )

router = APIRouter()

# ---------------------------------------------------------------------------
# PURE NVIDIA MODEL COMPARE (Batting & Bowling) — ZERO OpenCV
# ---------------------------------------------------------------------------
@router.post("/coach/diff")
async def compare_videos(
    left: UploadFile = File(...),
    right: UploadFile = File(...),
    prompt: str | None = Form(None),
    discipline: str | None = Form(None),
):
    if not is_nvidia_available():
        return {
            "status": "failed",
            "difference": "AI Coach is temporarily unavailable. Please try again."
        }

    async def save_temp(upload: UploadFile) -> tuple[str, bytes]:
        await upload.seek(0)
        content = await upload.read()
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
        tmp.write(content)
        tmp.close()
        return tmp.name, content

    left_path, left_bytes = await save_temp(left)
    right_path, right_bytes = await save_temp(right)

    try:
        disc_label = (discipline or "").strip().lower()
        if disc_label not in ("batting", "bowling"):
            disc_label = "cricket technique"

        left_frames = []
        right_frames = []
        try:
            with ThreadPoolExecutor(max_workers=2) as executor:
                f1 = executor.submit(extract_video_keyframes, left_path, 2)
                f2 = executor.submit(extract_video_keyframes, right_path, 2)
                left_frames = f1.result(timeout=15.0) or []
                right_frames = f2.result(timeout=15.0) or []
        except Exception:
            left_frames = extract_video_keyframes(left_path, max_frames=2)
            right_frames = extract_video_keyframes(right_path, max_frames=2)

        base_prompt = (prompt or "").strip()
        if not base_prompt or "video 1:" in base_prompt.lower():
            base_prompt = f"""You are a professional, India-level cricket {disc_label} coach.
Compare the player's {disc_label} technique between Video 1 and Video 2.
Return EXACTLY these 4 comparison points followed by a Final Verdict, and nothing else. No extra intro, no filler words:

1. Video 1 (What is good): [What worked well and positive technical aspect in Video 1]
2. Video 1 (What is bad): [Primary technical mistake and flaw in Video 1]
3. Video 2 (What is good): [Visible improvement and what worked well in Video 2]
4. Video 2 (What is bad): [Technical flaw that still needs correction in Video 2]

Final Verdict: [Clear coaching summary and verdict comparing both videos]

Do not add any other sentence, explanation, or heading."""

        diff_text = generate_nvidia_comparison_vision(
            prompt=base_prompt,
            discipline=disc_label,
            left_frames=left_frames,
            right_frames=right_frames,
            left_video_bytes=left_bytes,
            right_video_bytes=right_bytes,
            system_instruction=f"You are a professional, India-level cricket {disc_label} coach. Compare both videos strictly using the 4 points and Final Verdict.",
            model=NVIDIA_MODEL,
            max_output_tokens=4096,
            temperature=0.30,
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
            try:
                os.remove(left_path)
            except Exception:
                pass
        if os.path.exists(right_path):
            try:
                os.remove(right_path)
            except Exception:
                pass
