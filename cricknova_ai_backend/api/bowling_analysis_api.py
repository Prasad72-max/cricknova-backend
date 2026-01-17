from fastapi import APIRouter, UploadFile, File
import tempfile
import os

from cricknova_engine.processing.frame_extractor import extract_frames
from cricknova_engine.processing.ball_tracker import track_ball
from cricknova_engine.processing.speed import calculate_speed
from cricknova_engine.processing.swing import calculate_swing
from cricknova_engine.processing.spin import calculate_spin
from cricknova_engine.processing.trajectory import get_trajectory

router = APIRouter()

@router.post("/analyze/bowling")
async def analyze_bowling(video: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        tmp.write(await video.read())
        video_path = tmp.name

    frames = extract_frames(video_path)
    ball_positions = track_ball(frames)

    speed = calculate_speed(ball_positions)
    swing = calculate_swing(ball_positions)
    spin = calculate_spin(ball_positions)
    trajectory = get_trajectory(ball_positions)

    os.remove(video_path)

    return {
        "speed": round(speed, 2),
        "swing": round(swing, 2),
        "spin": int(spin),
        "trajectory": trajectory
    }
