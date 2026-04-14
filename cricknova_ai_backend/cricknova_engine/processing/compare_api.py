from fastapi import APIRouter, UploadFile, File
import tempfile
import os
from dotenv import load_dotenv
from gemini_text import generate_text

from processing.ball_tracker_motion import track_ball_positions
from cricknova_engine.processing.routes.spacefoco_backend import detect_swing_x, calculate_spin_real

load_dotenv()

router = APIRouter()


@router.post("/coach/diff")
async def compare_videos(
    left: UploadFile = File(...),
    right: UploadFile = File(...)
):
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        return {
            "status": "failed",
            "difference": "AI Coach is not configured yet. Please try again later."
        }

    def save_temp(upload: UploadFile):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
        tmp.write(upload.file.read())
        tmp.close()
        return tmp.name

    left_path = save_temp(left)
    right_path = save_temp(right)

    try:
        try:
            left_positions = track_ball_positions(left_path)
        except Exception:
            left_positions = []
        try:
            right_positions = track_ball_positions(right_path)
        except Exception:
            right_positions = []

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

Explain the technical differences line by line.
Focus on stance, head position, balance, bat path, timing, and shot selection.
Keep it concise and professional.
"""

        diff_text = generate_text(
            system_instruction="You are a professional cricket batting coach.",
            user_prompt=prompt,
            max_output_tokens=220,
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
