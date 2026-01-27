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
    if not positions or fps <= 0:
        return None

    dt = 1.0 / fps
    velocities = []

    # Cricket ball diameter ≈ 0.072 m
    BALL_DIAMETER_M = 0.072

    xs = [p[0] for p in positions]
    ys = [p[1] for p in positions]

    span_pixels = max(
        max(xs) - min(xs),
        max(ys) - min(ys),
        1
    )

    # More tolerant empirical scaling
    pixels_per_meter = span_pixels / (18 * BALL_DIAMETER_M)
    meters_per_pixel = 1.0 / pixels_per_meter

    for i in range(1, len(positions)):
        x0, y0 = positions[i - 1]
        x1, y1 = positions[i]

        pixel_dist = math.hypot(x1 - x0, y1 - y0)
        speed_mps = (pixel_dist * meters_per_pixel) / dt

        # Wide physics-safe bounds
        if 6 <= speed_mps <= 55:
            velocities.append(speed_mps)

    if not velocities:
        return None

    velocities.sort()

    # Robust median-based estimate
    mid = len(velocities) // 2
    if len(velocities) >= 3:
        core = velocities[max(0, mid - 1): min(len(velocities), mid + 2)]
    else:
        core = velocities

    final_speed_mps = sum(core) / len(core)
    final_speed_kmph = final_speed_mps * 3.6

    # Realistic cricket speed window
    final_speed_kmph = max(65.0, min(final_speed_kmph, 160.0))

    return round(final_speed_kmph, 1)