from fastapi import FastAPI, UploadFile, File
from ultralytics import YOLO
import cv2
import numpy as np
import math
import time

app = FastAPI()

app.state.last_pos = []
app.state.last_time = []

model = YOLO("yolo11n.pt")  # cricket ball trained model

# Realistic pitch-based scaling (22 yards ≈ 20.12 meters)
PITCH_LENGTH_METERS = 20.12


@app.post("/analyze_live_frame")
async def analyze_live_frame(file: UploadFile = File(...)):
    # read frame
    img_bytes = await file.read()
    nparr = np.frombuffer(img_bytes, np.uint8)
    frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    # detect ball
    results = model.predict(frame, conf=0.5)
    boxes = results[0].boxes.xyxy.cpu().numpy()

    if len(boxes) == 0:
        return {"found": False}

    x1, y1, x2, y2 = boxes[0]
    cx = int((x1 + x2) / 2)
    cy = int((y1 + y2) / 2)

    # track previous positions
    last_pos = app.state.last_pos
    last_pos.append((cx, cy))
    if len(last_pos) > 12:
        last_pos.pop(0)

    # -----------------------------
    # REAL PHYSICS SPEED (NON-SCRIPTED)
    # -----------------------------
    last_time = app.state.last_time
    now = time.time()
    last_time.append(now)
    if len(last_time) > 12:
        last_time.pop(0)

    speed_range = None

    if len(last_pos) >= 6 and len(last_time) >= 6:
        # Use last 5 segments for stability
        distances = []
        times = []

        for i in range(-5, -1):
            d_px = math.dist(last_pos[i], last_pos[i + 1])
            dt = last_time[i + 1] - last_time[i]
            if dt > 0:
                distances.append(d_px)
                times.append(dt)

        if distances and times:
            avg_px_per_sec = (sum(distances) / sum(times))

            # Estimate pitch pixel length dynamically
            ys = [p[1] for p in last_pos]
            pitch_px = max(200.0, max(ys) - min(ys))
            meters_per_pixel = PITCH_LENGTH_METERS / pitch_px

            speed_mps = avg_px_per_sec * meters_per_pixel
            speed_kmh_calc = speed_mps * 3.6

            # Cricket-realistic envelope (physics-based, no confidence, no scripting)
            if 60 <= speed_kmh_calc <= 165:
                spread = max(6.0, speed_kmh_calc * 0.06)
                speed_range = {
                    "min": int(round(speed_kmh_calc - spread)),
                    "max": int(round(speed_kmh_calc + spread))
                }

    # SWING CALCULATION
    if len(last_pos) > 4:
        x_start, y_start = last_pos[0]
        x_end, y_end = last_pos[-1]
        swing_angle = math.degrees(math.atan2((y_end - y_start),
                                              (x_end - x_start)))
    else:
        swing_angle = 0

    return {
        "found": True,
        "speed_kmph": speed_range,
        "swing_angle": round(swing_angle, 2),
        "path": last_pos
    }
