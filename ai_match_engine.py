from fastapi import FastAPI, UploadFile, File
import uvicorn
import random

app = FastAPI()

# -----------------------------
# AI ENGINE (MOCK VERSION NOW)
# -----------------------------

def analyze_video_frame(frame_bytes: bytes):
    """
    This function will later be replaced with your YOLO + OpenCV AI.
    For now, we simulate perfect ball analysis.
    """

    # RANDOM VALUES (AI WILL REPLACE)
    ball_speed = round(random.uniform(118, 146), 2)
    swing = round(random.uniform(-2.5, 2.5), 2)
    spin = random.randint(400, 1200)   # rpm
    timing_score = random.randint(40, 100)
    power_score = random.randint(30, 95)

    shot_dirs = ["cover", "midwicket", "straight", "square", "fine_leg"]
    direction = random.choice(shot_dirs)

    # RUN LOGIC (WILL BE AI LATER)
    if power_score > 80:
        predicted = 6
    elif timing_score > 70:
        predicted = 4
    elif timing_score < 45:
        predicted = 0
    else:
        predicted = random.choice([1, 2, 3])

    return {
        "ball_speed": ball_speed,
        "swing": swing,
        "spin": spin,
        "timing_score": timing_score,
        "power_score": power_score,
        "shot_direction": direction,
        "predicted_runs": predicted,
        "impact_detected": True
    }

# ----------------------------------------
# FASTAPI endpoint
# ----------------------------------------
@app.post("/analyze_delivery")
async def analyze_delivery(video: UploadFile = File(...)):
    """
    1 ball video → returns everything AI detects.
    """

    file_bytes = await video.read()

    result = analyze_video_frame(file_bytes)

    return {
        "status": "success",
        "analysis": result
    }


if __name__ == "__main__":
    uvicorn.run("ai_match_engine:app", host="0.0.0.0", port=8001, reload=True)