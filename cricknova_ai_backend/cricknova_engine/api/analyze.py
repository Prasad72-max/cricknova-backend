import tempfile
import shutil

async def analyze_video(file):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        shutil.copyfileobj(file.file, tmp)
        video_path = tmp.name

    # Final clean JSON that matches Flutter requirements
    return {
        "ball_speed": 129.4,
        "swing_angle": -2.3,
        "spin_rate": 850,
        "trajectory": [1, 2, 3],
        "pitch_map": [4, 5, 6],
        "release_point": [7, 8, 9],
        "status": "ok"
    }