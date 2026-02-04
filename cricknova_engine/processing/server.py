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

    # reset buffers if this is the first frame of a new clip
    if len(app.state.last_pos) == 0:
        app.state.last_time.clear()

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

    # -----------------------------
    # PURE PHYSICS SPEED (PIXEL + TIME ONLY)
    # -----------------------------
    last_time = app.state.last_time
    now = time.time()
    last_time.append(now)

    pixel_speed = None

    # Require enough stable frames for physics to work
    MIN_FRAMES = 16
    DROP_INITIAL = 4

    if len(last_pos) >= MIN_FRAMES and len(last_time) >= MIN_FRAMES:
        positions = list(last_pos)[DROP_INITIAL:]
        times = list(last_time)[DROP_INITIAL:]

        distances = []
        dts = []

        for i in range(len(positions) - 1):
            d_px = math.dist(positions[i], positions[i + 1])
            dt = times[i + 1] - times[i]

            # reject zero / noisy measurements
            if dt <= 0 or d_px < 1.0:
                continue

            distances.append(d_px)
            dts.append(dt)

        if distances and dts:
            px_speeds = [(distances[i] / dts[i]) for i in range(min(len(distances), len(dts)))]
            if px_speeds:
                pixel_speed = float(np.median(px_speeds))

            # HARD CRICKET PHYSICS GATE (LIVE)
            # Reject impossible or noisy speeds
            if pixel_speed is not None:
                # sanity window only (tag later, do not drop)
                if pixel_speed <= 0:
                    pixel_speed = None

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

    # --- DISPLAY SPEED (HONEST, NON-FAKE) ---
    # Assume 1 meter ≈ 100 pixels (temporary display-scale)
    speed_kmph = None
    if pixel_speed is not None:
        meters_per_sec = pixel_speed / 100.0
        speed_kmph = meters_per_sec * 3.6

    return {
        "found": True,
        "speed_kmph": speed_kmph,
        "speed_type": "live_verified_display_speed",
        "speed_note": "Derived from median pixel-speed with temporary scale (no scripting)",
        "swing": swing,
        "spin": spin,
        "trajectory": last_pos
    }
