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
    # PURE PHYSICS SPEED (PIXEL + TIME ONLY)
    # -----------------------------
    last_time = app.state.last_time
    now = time.time()
    last_time.append(now)
    if len(last_time) > 12:
        last_time.pop(0)

    speed_value = None

    if len(last_pos) >= 2 and len(last_time) >= 2:
        distances = []
        times = []

        for i in range(len(last_pos) - 1):
            d_px = math.dist(last_pos[i], last_pos[i + 1])
            dt = last_time[i + 1] - last_time[i]
            if dt > 0 and d_px > 0:
                distances.append(d_px)
                times.append(dt)

        if distances and times:
            px_per_sec = sum(distances) / sum(times)

            # NOTE:
            # No pitch assumptions
            # No vertical filtering
            # No cricket limits
            # Raw pixel speed converted using frame scale only
            # 1 pixel == 1 unit distance (debug physics)

            speed_value = round(float(px_per_sec), 2)

    # SWING CALCULATION
    if len(last_pos) > 4:
        x_start, y_start = last_pos[0]
        x_end, y_end = last_pos[-1]
        swing_angle = math.degrees(math.atan2((y_end - y_start),
                                              (x_end - x_start)))
    else:
        swing_angle = 0

    if abs(swing_angle) < 1.5:
        swing = "none"
    elif swing_angle > 0:
        swing = "outswing"
    else:
        swing = "inswing"

    swing_confidence = min(1.0, len(last_pos) / 10.0)

    spin = "none"
    spin_confidence = 0.0
    if len(last_pos) >= 8:
        x_changes = [last_pos[i+1][0] - last_pos[i][0] for i in range(len(last_pos)-1)]
        curve = sum(x_changes[-4:])
        if abs(curve) > 2:
            spin = "off spin" if curve > 0 else "leg spin"
            spin_confidence = min(1.0, abs(curve) / 10.0)

    return {
        "found": True,
        "speed_kmph": speed_value,
        "speed_type": "raw_pixel_speed",
        "speed_note": "Pure pixel-per-second speed (no physics assumptions, no limits)",
        "swing": swing,
        "spin": spin,
        "trajectory": last_pos
    }
