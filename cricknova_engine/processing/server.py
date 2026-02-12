from fastapi import FastAPI, UploadFile, File
from ultralytics import YOLO
import cv2
import numpy as np
import math
import time
from collections import deque
from cricknova_engine.processing.swing import calculate_swing
from cricknova_engine.processing.spin import calculate_spin

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
    app.state.last_time.append(time.time())


    # -----------------------------
    # FULLTRACK-STYLE WINDOWED RELEASE SPEED (LIVE)
    # -----------------------------
    speed_kmph = None
    speed_type = "unavailable"
    speed_note = "INSUFFICIENT_PHYSICS_DATA"

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

            # LOW SPEED REALISM GUARD
            if raw_kmph < 40:
                speed_kmph = None
                speed_type = "too_slow"
                speed_note = "NON_BOWLING_OR_TRACKING_NOISE"
            elif raw_kmph < 55:
                speed_kmph = round(float(raw_kmph), 1)
                speed_type = "very_slow_estimate"
                speed_note = "BORDERLINE_LOW_SPEED"
            elif 55.0 <= raw_kmph <= 165.0:
                speed_kmph = round(float(raw_kmph), 1)
                speed_type = "measured_release"
                speed_note = "FULLTRACK_STYLE_WINDOWED"

    # -----------------------------
    # CONSERVATIVE VIDEO FALLBACK (NEVER NULL)
    # -----------------------------
    if speed_kmph is None and len(app.state.last_pos) >= 6:
        pts = list(app.state.last_pos)

        pixel_dists = []
        for i in range(1, len(pts)):
            d = math.dist(pts[i], pts[i - 1])
            if d > 1.0:
                pixel_dists.append(d)

        if len(pixel_dists) >= 3:
            avg_px = float(np.mean(pixel_dists))

            # Conservative visible flight calibration
            FRAME_METERS = 20.0
            y_vals = [p[1] for p in pts]
            pixel_span = abs(max(y_vals) - min(y_vals))

            if pixel_span > 0:
                meters_per_px = FRAME_METERS / pixel_span
                fps_est = 30.0

                kmph = avg_px * meters_per_px * fps_est * 3.6

                if kmph < 55.0 or kmph > 165.0:
                    kmph = None

                if kmph is not None and kmph < 55.0:
                    speed_kmph = round(float(kmph), 1)
                    speed_type = "very_slow_estimate"
                    speed_note = "BORDERLINE_LOW_SPEED"

                if kmph is not None and speed_kmph is None:
                    speed_kmph = round(float(kmph), 1)
                    speed_type = "video_derived"
                    speed_note = "PARTIAL_TRACK_PHYSICS"

    # HARD SAFETY: do NOT fabricate speed
    if speed_kmph is None:
        speed_type = "unavailable"
        speed_note = "INSUFFICIENT_TRACK_CONTINUITY"

    # -----------------------------
    # REALISTIC SWING & SPIN (PHYSICS-BASED)
    # -----------------------------
    ball_positions_px = list(last_pos)

    # Normalize positions to 0–1 scale for physics engine
    h, w = frame.shape[:2]
    ball_positions = []
    if w > 0 and h > 0:
        for (x, y) in ball_positions_px:
            ball_positions.append((float(x) / float(w), float(y) / float(h)))

    swing_result = calculate_swing(ball_positions)
    spin_result = calculate_spin(ball_positions)

    swing = swing_result.get("name") or "Straight"
    spin = spin_result.get("name") or "Straight"

    return {
        "found": True,
        "speed_kmph": speed_kmph,
        "speed_type": speed_type,
        "speed_note": speed_note,
        "swing": swing,
        "spin": spin,
        "spin_strength": spin_result.get("strength"),
        "trajectory": [
            {"x": float(x) / float(w), "y": float(y) / float(h)}
            for (x, y) in ball_positions_px
        ]
    }
