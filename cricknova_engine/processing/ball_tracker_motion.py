import cv2
import numpy as np
import math

MAX_EFFECTIVE_DISTANCE_METERS = 23.0  # max real ball travel (release → bat)

def track_ball_positions(video_path, max_frames=120):
    cap = cv2.VideoCapture(video_path)

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps is None or fps <= 1 or fps > 240:
        fps = 30.0
    fps = float(fps)
    # Normalize FPS to avoid variable-FPS instability (Render-safe)
    fps = min(max(fps, 24.0), 60.0)

    positions = []
    last_pos = None
    prev_gray = None
    frame_count = 0
    miss_count = 0

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
            if 18 < area < 900:
                (x, y, w, h) = cv2.boundingRect(c)
                cx = x + w // 2
                cy = y + h // 2

                if last_pos is None:
                    ball_candidate = (cx, cy)
                    break
                else:
                    dist = math.hypot(cx - last_pos[0], cy - last_pos[1])
                    if 1.2 < dist < min_dist:
                        min_dist = dist
                        ball_candidate = (cx, cy)

        if ball_candidate is None:
            # Allow brief occlusions without resetting physics history
            miss_count += 1
            # Do NOT reset last_pos; keep continuity for speed physics
            prev_gray = gray
            continue
        else:
            miss_count = 0
            positions.append(ball_candidate)
            last_pos = ball_candidate
        prev_gray = gray

        # stop early only if enough stable points found (Render-safe)
        # lowered threshold to allow short but physically valid clips
        if len(positions) >= 12:
            break

    cap.release()
    return positions, fps


# --- Ball speed calculation utility ---
def calculate_ball_speed_kmph(positions, fps):
    """
    Physics-based speed calculation (camera-normalized).
    - Uses pixel motion + real FPS
    - Returns speed only when motion-based physics is valid
    """

    if not positions or fps <= 0 or len(positions) < 4:
        return {
            "speed_px_per_sec": None,
            "speed_kmph": None,
            "speed_type": "unavailable",
            "confidence": 0.0,
            "speed_note": "INSUFFICIENT_PHYSICS_DATA"
        }

    velocities = []

    for i in range(1, len(positions)):
        x0, y0 = positions[i - 1]
        x1, y1 = positions[i]
        d = math.hypot(x1 - x0, y1 - y0)

        # physically continuous motion only
        if 0.8 < d < 260:
            velocities.append(d * fps)

    if len(velocities) < 2:
        return {
            "speed_px_per_sec": None,
            "speed_kmph": None,
            "speed_type": "unavailable",
            "confidence": 0.0,
            "speed_note": "INSUFFICIENT_PHYSICS_DATA"
        }

    px_per_sec = float(np.median(velocities))

    # --- BOUNDED REAL-WORLD PHYSICS (NO SCRIPTING) ---
    xs = [p[0] for p in positions]
    ys = [p[1] for p in positions]
    total_px = math.hypot(xs[-1] - xs[0], ys[-1] - ys[0])

    if total_px <= 0:
        return {
            "speed_px_per_sec": None,
            "speed_kmph": None,
            "speed_type": "unavailable",
            "confidence": 0.0,
            "speed_note": "INVALID_PIXEL_DISTANCE"
        }

    meters_per_px = MAX_EFFECTIVE_DISTANCE_METERS / total_px
    speed_kmph = px_per_sec * meters_per_px * 3.6

    if speed_kmph <= 0 or speed_kmph > 170:
        return {
            "speed_px_per_sec": round(px_per_sec, 2),
            "speed_kmph": None,
            "speed_type": "unavailable",
            "confidence": 0.0,
            "speed_note": "PHYSICS_OUT_OF_RANGE"
        }

    return {
        "speed_px_per_sec": round(px_per_sec, 2),
        "speed_kmph": round(float(speed_kmph), 1),
        "speed_type": "camera_estimated",
        "confidence": round(min(1.0, len(velocities) / 10.0), 2),
        "speed_note": "bounded_real_physics"
    }

# --- Swing & Spin detection (physics-based, no heuristics UI-side) ---

def calculate_swing_type(positions):
    """
    Detects swing using lateral deviation during flight.
    Returns: 'inswing', 'outswing', or 'none'
    """
    if not positions or len(positions) < 6:
        return "none"

    xs = [p[0] for p in positions]

    early_mean = np.mean(xs[: len(xs)//3])
    late_mean = np.mean(xs[-len(xs)//3 :])

    dx = late_mean - early_mean

    if abs(dx) < 6:
        return "none"
    return "inswing" if dx < 0 else "outswing"


def calculate_spin_type(positions):
    """
    Detects spin using post-pitch sideways drift.
    Returns: 'off spin', 'leg spin', or 'none'
    """
    if not positions or len(positions) < 8:
        return "none"

    ys = [p[1] for p in positions]
    pitch_idx = int(np.argmax(ys))

    if pitch_idx >= len(positions) - 4:
        return "none"

    xs_after = [positions[i][0] for i in range(pitch_idx, len(positions))]
    drift = xs_after[-1] - xs_after[0]

    if abs(drift) < 5:
        return "none"
    return "off spin" if drift < 0 else "leg spin"