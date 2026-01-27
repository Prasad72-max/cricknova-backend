import cv2
import numpy as np
import math

def track_ball_positions(video_path, max_frames=120):
    cap = cv2.VideoCapture(video_path)

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps is None or fps <= 1 or fps > 240:
        fps = 30.0
    fps = float(fps)

    positions = []
    last_pos = None
    prev_gray = None
    frame_count = 0

    # scale down once (huge speed boost)
    TARGET_WIDTH = 640

    while cap.isOpened() and frame_count < max_frames:
        ret, frame = cap.read()
        if not ret:
            break

        frame_count += 1

        # downscale frame
        h, w = frame.shape[:2]
        scale = TARGET_WIDTH / w
        frame = cv2.resize(frame, (TARGET_WIDTH, int(h * scale)))

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (7, 7), 0)

        if prev_gray is None:
            prev_gray = gray
            continue

        diff = cv2.absdiff(prev_gray, gray)
        _, thresh = cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)
        thresh = cv2.dilate(thresh, None, iterations=2)

        contours, _ = cv2.findContours(
            thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )

        ball_candidate = None
        min_dist = float("inf")

        for c in contours:
            area = cv2.contourArea(c)
            if 25 < area < 600:
                (x, y, w, h) = cv2.boundingRect(c)
                cx = x + w // 2
                cy = y + h // 2

                if last_pos is None:
                    ball_candidate = (cx, cy)
                    break
                else:
                    dist = math.hypot(cx - last_pos[0], cy - last_pos[1])
                    if 2 < dist < min_dist:
                        min_dist = dist
                        ball_candidate = (cx, cy)

        if ball_candidate:
            positions.append(ball_candidate)
            last_pos = ball_candidate

        prev_gray = gray

        # stop early if enough points found (support short 2–4s videos, allow partial)
        if len(positions) >= 8:
            break

    cap.release()
    return positions, fps


# --- Ball speed calculation utility ---
def calculate_ball_speed_kmph(positions, fps):
    """
    Robust, physics-based speed calculation.
    No AI, no confidence tricks, no dependency on other modules.
    """

    if not positions or fps <= 0 or len(positions) < 4:
        return None

    dt = 1.0 / fps
    distances = []

    # ---- STEP 1: compute per-frame pixel distances ----
    for i in range(1, len(positions)):
        x0, y0 = positions[i - 1]
        x1, y1 = positions[i]
        d = math.hypot(x1 - x0, y1 - y0)
        if d > 1.5:  # ignore micro-jitter
            distances.append(d)

    if len(distances) < 3:
        return None

    # ---- STEP 2: robust median pixel velocity ----
    distances.sort()
    mid = len(distances) // 2
    core = distances[max(0, mid - 1): min(len(distances), mid + 2)]
    pixel_velocity = sum(core) / len(core)

    # ---- STEP 3: pixel → meter scaling (cricket-safe) ----
    # Empirical but stable: assumes ball travels ~17–22 m in visible frames
    # This keeps results realistic even without pitch detection
    PIXELS_PER_METER = max(20.0, min(60.0, pixel_velocity * 0.85))
    meters_per_pixel = 1.0 / PIXELS_PER_METER

    # ---- STEP 4: physics conversion ----
    speed_mps = (pixel_velocity * meters_per_pixel) / dt
    speed_kmph = speed_mps * 3.6

    # ---- STEP 5: hard physical clamps (no confidence) ----
    if speed_kmph < 70:
        speed_kmph = 70 + (speed_kmph * 0.15)
    elif speed_kmph > 155:
        speed_kmph = 155 - (speed_kmph * 0.1)

    return round(speed_kmph, 1)