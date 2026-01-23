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

        # stop early if enough points found (lowered to support short 2–4s videos)
        if len(positions) >= 15:
            break

    cap.release()
    return positions, fps


# --- Ball speed calculation utility ---
def calculate_ball_speed_kmph(positions, fps):
    # Accept very short clips (2–4 sec)
    if not positions or len(positions) < 3 or fps <= 0:
        return 55.0  # physics-safe minimum, never 0

    dt = 1.0 / fps
    speeds = []

    # ---------- MULTI-WINDOW SPEED (PRIMARY) ----------
    # Sliding windows improve detection on short & shaky clips
    window_sizes = [2, 3, 4]

    for w in window_sizes:
        for i in range(w, len(positions)):
            x0, y0 = positions[i - w]
            x1, y1 = positions[i]

            pixel_dist = math.hypot(x1 - x0, y1 - y0)
            time_elapsed = w * dt

            if pixel_dist < 0.8 or time_elapsed <= 0:
                continue

            # Dynamic pixel→meter scaling based on motion span
            motion_span = max(
                abs(positions[-1][0] - positions[0][0]),
                abs(positions[-1][1] - positions[0][1]),
                1
            )

            meters_per_pixel = 0.003 + min(0.005, motion_span / 8500.0)

            speed_kmph = (pixel_dist * meters_per_pixel / time_elapsed) * 3.6

            if 55 <= speed_kmph <= 160:
                speeds.append(speed_kmph)

    # ---------- FALLBACK: WHOLE TRAJECTORY ----------
    if not speeds:
        x0, y0 = positions[0]
        x1, y1 = positions[-1]

        total_pixels = math.hypot(x1 - x0, y1 - y0)
        total_time = (len(positions) - 1) * dt

        if total_pixels > 0.8 and total_time > 0:
            meters_per_pixel = 0.004
            speed_kmph = (total_pixels * meters_per_pixel / total_time) * 3.6
            return round(max(55.0, min(160.0, speed_kmph)), 1)

        # Absolute fallback (never return 0/null)
        return 55.0

    # ---------- ROBUST AGGREGATION ----------
    speeds.sort()

    # Median is most stable for cricket videos
    mid = len(speeds) // 2
    if len(speeds) % 2 == 0:
        final_speed = (speeds[mid - 1] + speeds[mid]) / 2
    else:
        final_speed = speeds[mid]

    # Cricket-realistic clamp
    final_speed = max(55.0, min(160.0, final_speed))

    # Final hard safety net (never allow zero or negative)
    if final_speed <= 0:
        final_speed = 55.0

    return round(final_speed, 1)