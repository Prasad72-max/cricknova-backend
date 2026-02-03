import cv2 as cv
import numpy as np
import math

# Physical human bowling limits (km/h)
MIN_VALID_SPEED = 40.0
MAX_VALID_SPEED = 170.0

def filter_positions(ball_positions):
    """
    Removes noisy jumps and keeps physically plausible motion.
    """
    if not ball_positions:
        return []

    filtered = [ball_positions[0]]
    for x, y, f in ball_positions[1:]:
        lx, ly, lf = filtered[-1]
        dist = math.hypot(x - lx, y - ly)

        # Reject noise and sudden jumps
        if 1.5 < dist < 50:
            filtered.append((x, y, f))

    return filtered

def track_ball_positions(video_path):
    cap = cv.VideoCapture(video_path)
    fps = cap.get(cv.CAP_PROP_FPS)
    if fps is None or fps <= 1:
        fps = 30.0
    ball_positions = []
    prev_center = None
    frame_idx = 0

    backSub = cv.createBackgroundSubtractorMOG2(
        history=200,
        varThreshold=25,
        detectShadows=False
    )

    def distance(p1, p2):
        return math.hypot(p1[0] - p2[0], p1[1] - p2[1])

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        frame_idx += 1

        gray = cv.cvtColor(frame, cv.COLOR_BGR2GRAY)
        blur = cv.GaussianBlur(gray, (9, 9), 0)

        # --- Foreground motion mask ---
        fg_mask = backSub.apply(blur)
        fg_mask = cv.medianBlur(fg_mask, 5)

        contours, _ = cv.findContours(
            fg_mask, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE
        )

        candidates = []

        for cnt in contours:
            area = cv.contourArea(cnt)
            if 30 < area < 2500:
                (x, y), radius = cv.minEnclosingCircle(cnt)
                if 4 < radius < 30:
                    candidates.append((int(x), int(y)))

        chosen = None

        # --- Prefer contour-based motion ---
        if candidates:
            if prev_center:
                chosen = min(
                    candidates,
                    key=lambda c: distance(c, prev_center)
                )
            else:
                chosen = candidates[0]

        # --- Fallback to Hough if needed ---
        if chosen is None:
            circles = cv.HoughCircles(
                blur,
                cv.HOUGH_GRADIENT,
                dp=1.3,
                minDist=80,
                param1=120,
                param2=28,
                minRadius=6,
                maxRadius=30
            )

            if circles is not None:
                circles = np.uint16(np.around(circles))
                if prev_center:
                    chosen = min(
                        [(c[0], c[1]) for c in circles[0]],
                        key=lambda c: distance(c, prev_center)
                    )
                else:
                    chosen = (circles[0][0][0], circles[0][0][1])

        if chosen is not None:
            ball_positions.append((chosen[0], chosen[1], frame_idx))
            prev_center = chosen

    # Final cleanup
    ball_positions = filter_positions(ball_positions)

    cap.release()
    return ball_positions, fps


# --- Physics-based speed calculator ---
def compute_speed_kmph(ball_positions, fps):
    """
    Physics-based speed estimation from frame-to-frame motion.
    Returns speed only.
    No scripted fallbacks or clamps.
    """

    # Fallback if tracking is insufficient
    if not ball_positions or fps <= 1:
        return {
            "speed_kmph": None
        }

    xs = [p[0] for p in ball_positions]
    ys = [p[1] for p in ball_positions]
    fs = [p[2] for p in ball_positions]

    # Detect pitch (max Y in camera space)
    pitch_idx = int(np.argmax(ys))
    if pitch_idx < 3:
        pitch_idx = min(len(ys) - 1, 3)

    start = max(1, pitch_idx - 8)
    end = pitch_idx

    distances = []
    times = []

    for i in range(start, end):
        x0, y0, f0 = xs[i - 1], ys[i - 1], fs[i - 1]
        x1, y1, f1 = xs[i], ys[i], fs[i]

        df = f1 - f0
        if df <= 0:
            continue

        dp = math.hypot(x1 - x0, y1 - y0)

        # Strong noise rejection
        if dp < 2.0 or dp > 40.0:
            continue

        distances.append(dp)
        times.append(df / fps)

    if len(distances) < 2:
        return {
            "speed_kmph": None
        }

    median_px = sum(distances) / len(distances)

    # Estimate pitch length in pixels
    pitch_px = max(220.0, np.percentile(ys, 90) - np.percentile(ys, 10))
    meters_per_pixel = 20.12 / pitch_px

    speed_mps = (median_px * meters_per_pixel) / np.median(times)

    speed_kmph = speed_mps * 3.6

    # -----------------------------
    # PHYSICS VALIDATION (NO SCRIPTING)
    # -----------------------------
    # Reject clearly impossible values instead of clamping
    if speed_kmph < MIN_VALID_SPEED or speed_kmph > MAX_VALID_SPEED:
        return {
            "speed_kmph": None
        }

    return {
        "speed_kmph": round(float(speed_kmph), 1)
    }

def compute_swing(ball_positions):
    """
    Simple physics-based swing detection using lateral deviation.
    Returns: 'inswing', 'outswing', or 'none'
    """
    if not ball_positions or len(ball_positions) < 6:
        return {"swing": "none", "confidence": 0.0}

    xs = [p[0] for p in ball_positions]
    ys = [p[1] for p in ball_positions]

    # Compare early vs late lateral movement
    early_x = np.mean(xs[: len(xs)//3])
    late_x = np.mean(xs[-len(xs)//3 :])

    dx = late_x - early_x

    if abs(dx) < 2:
        return {"swing": "none", "confidence": 0.0}

    confidence = min(1.0, abs(dx) / 12.0)
    return {
        "swing": "inswing" if dx < 0 else "outswing",
        "confidence": round(confidence, 2)
    }


def compute_spin(ball_positions):
    """
    Motion-based spin inference.
    Returns: 'off spin', 'leg spin', or 'none'
    """
    if not ball_positions or len(ball_positions) < 8:
        return {"spin": "none", "confidence": 0.0}

    xs = [p[0] for p in ball_positions]
    ys = [p[1] for p in ball_positions]

    # Look for sideways drift after bounce
    pitch_idx = int(np.argmax(ys))
    if pitch_idx >= len(xs) - 4:
        return {"spin": "none", "confidence": 0.0}

    post_x = xs[pitch_idx:]
    drift = post_x[-1] - post_x[0]

    if abs(drift) < 2:
        return {"spin": "none", "confidence": 0.0}

    confidence = min(1.0, abs(drift) / 10.0)
    return {
        "spin": "off spin" if drift < 0 else "leg spin",
        "confidence": round(confidence, 2)
    }