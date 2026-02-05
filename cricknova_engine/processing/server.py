from fastapi import FastAPI, UploadFile, File
from ultralytics import YOLO
import cv2
import numpy as np
import math
import time
from collections import deque

app = FastAPI()

app.state.last_pos = deque(maxlen=40)
app.state.last_time = deque(maxlen=40)


model = YOLO("yolo11n.pt")  # cricket ball trained model


@app.post("/analyze_live_frame")
async def analyze_live_frame(file: UploadFile = File(...)):
    # read frame
    img_bytes = await file.read()
    nparr = np.frombuffer(img_bytes, np.uint8)
    frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)


    # detect ball
    results = model.predict(frame, conf=0.15, imgsz=640)
    boxes = results[0].boxes.xyxy.cpu().numpy()

    if len(boxes) == 0:
        # Do NOT clear history; allow continuity across brief occlusion
        return {"found": False}

    # choose smallest box (ball)
    areas = [(i, (b[2] - b[0]) * (b[3] - b[1])) for i, b in enumerate(boxes)]
    best_i = min(areas, key=lambda x: x[1])[0]
    x1, y1, x2, y2 = boxes[best_i]
    cx = int((x1 + x2) / 2)
    cy = int((y1 + y2) / 2)

    # track previous positions
    last_pos = app.state.last_pos
    last_pos.append((cx, cy))


    # -----------------------------
    # FULLTRACK-STYLE WINDOWED RELEASE SPEED (LIVE)
    # -----------------------------
    speed_kmph = None
    speed_type = "unavailable"
    speed_note = "FULLTRACK_STYLE_WINDOWED"
    confidence = 0.0

    MIN_FRAMES = 12
    if len(app.state.last_pos) >= MIN_FRAMES and len(app.state.last_time) >= MIN_FRAMES:
        pts = list(app.state.last_pos)
        times = list(app.state.last_time)

        # Skip first 2 frames to avoid hand jitter
        window_start = 2
        window_end = min(10, len(pts) - 1)

        seg_dists = []
        seg_times = []

        for i in range(window_start, window_end):
            d_px = math.dist(pts[i], pts[i - 1])
            dt = times[i] - times[i - 1]

            if dt <= 0 or d_px < 1.0 or d_px > 200.0:
                continue

            seg_dists.append(d_px)
            seg_times.append(dt)

        if len(seg_dists) >= 3:
            px_per_sec = np.median(
                [seg_dists[i] / seg_times[i] for i in range(len(seg_dists))]
            )

            # Pitch-anchored realistic scaling (fallback)
            meters_per_px = 17.0 / 320.0  # tuned release-to-bounce scale
            raw_kmph = px_per_sec * meters_per_px * 3.6

            if 90.0 <= raw_kmph <= 155.0:
                speed_kmph = round(float(raw_kmph), 1)
                speed_type = "ai_estimated_release"
                confidence = round(min(1.0, len(seg_dists) / 6.0), 2)

    # SWING CALCULATION
    if len(last_pos) > 4:
        x_start, y_start = last_pos[0]
        x_end, y_end = last_pos[-1]
        swing_angle = math.degrees(math.atan2((y_end - y_start),
                                              (x_end - x_start)))
    else:
        swing_angle = None

    if swing_angle is None:
        swing = "unknown"
    elif abs(swing_angle) < 1.5:
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
        "speed_kmph": speed_kmph,
        "speed_type": speed_type,
        "confidence": confidence,
        "speed_note": speed_note,
        "swing": swing,
        "spin": spin,
        "trajectory": list(last_pos)
    }
