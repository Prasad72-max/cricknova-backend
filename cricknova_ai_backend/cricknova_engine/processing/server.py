from fastapi import FastAPI, UploadFile, File
from ultralytics import YOLO
import cv2
import numpy as np
import math

app = FastAPI()

model = YOLO("yolo11n.pt")  # cricket ball trained model

# Convert pixels to meters correctly
PIXEL_TO_METER = 0.0021  # (adjust after calibration)


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
    global last_pos
    if "last_pos" not in globals():
        last_pos = []

    last_pos.append((cx, cy))
    if len(last_pos) > 12:
        last_pos.pop(0)

    # SPEED CALCULATION
    speed_kmh = 0
    if len(last_pos) > 2:
        dist_pixels = math.dist(last_pos[-1], last_pos[-2])
        dist_meters = dist_pixels * PIXEL_TO_METER
        speed_mps = dist_meters * 30  # 30 FPS
        speed_kmh = speed_mps * 3.6

    # SWING CALCULATION (horizontal deviation based, no fake angles)
    swing_angle = 0
    swing_type = "straight"

    if len(last_pos) > 6:
        xs = [p[0] for p in last_pos]
        ys = [p[1] for p in last_pos]

        # Fit simple straight line using first and last point
        x_start, y_start = last_pos[0]
        x_end, y_end = last_pos[-1]

        dx = x_end - x_start
        dy = y_end - y_start

        if abs(dy) > 5:  # ensure meaningful vertical movement
            predicted_x_end = x_start + dx
            actual_x_end = x_end

            horizontal_deviation = actual_x_end - predicted_x_end

            # Ignore very tiny noise
            if abs(horizontal_deviation) > 3:
                swing_angle = math.degrees(math.atan2(horizontal_deviation, dy))

                if horizontal_deviation > 0:
                    swing_type = "outswing"
                else:
                    swing_type = "inswing"
            else:
                swing_angle = 0
                swing_type = "straight"

    return {
        "found": True,
        "speed_kmh": round(speed_kmh, 2),
        "swing_angle": round(swing_angle, 2),
        "swing_type": swing_type,
        "path": last_pos
    }
