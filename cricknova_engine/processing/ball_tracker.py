import cv2 as cv
import numpy as np
import math

# --- LEGACY CONSERVATIVE VIDEO-DRIVEN SPEED (RESTORED) ---
def compute_speed_kmph(ball_positions, fps=30):
    """
    Conservative, non-scripted, video-driven bowling speed.
    Restored to ensure speed appears on most usable videos.
    """

    if not ball_positions or fps <= 0 or len(ball_positions) < fps // 2:
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "INSUFFICIENT_FRAMES"
        }

    pixel_dists = []
    for i in range(1, len(ball_positions)):
        x1, y1 = ball_positions[i - 1][0], ball_positions[i - 1][1]
        x2, y2 = ball_positions[i][0], ball_positions[i][1]
        d = math.hypot(x2 - x1, y2 - y1)
        if d > 0:
            pixel_dists.append(d)

    if not pixel_dists:
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "NO_PIXEL_MOTION"
        }

    pixel_dists = np.array(pixel_dists)

    # Remove jitter (bottom 25%)
    pixel_dists = pixel_dists[pixel_dists > np.percentile(pixel_dists, 25)]
    if len(pixel_dists) == 0:
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "JITTER_ONLY"
        }

    avg_px_per_frame = float(np.mean(pixel_dists))

    # Vertical span drives calibration
    ys = [p[1] for p in ball_positions]
    pixel_span = abs(max(ys) - min(ys))
    if pixel_span <= 0:
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "ZERO_SPAN"
        }

    FRAME_METERS = 20.0  # same as last-month production behavior
    meters_per_pixel = FRAME_METERS / pixel_span

    meters_per_sec = avg_px_per_frame * meters_per_pixel * fps
    kmph = meters_per_sec * 3.6

    # Conservative smoothing (last-month behavior)
    kmph = kmph * 0.85

    return {
        "speed_kmph": round(float(kmph), 1),
        "speed_type": "video_derived",
        "speed_note": "LEGACY_CONSERVATIVE"
    }


# --- Unified Speed API Wrapper ---
def calculate_ball_speed_kmph(ball_positions, fps):
    """
    Backward-compatible wrapper used by server and motion modules.
    """
    return compute_speed_kmph(ball_positions, fps)

# --- BOUNDED REAL-WORLD TRAVEL ---
MAX_EFFECTIVE_DISTANCE_METERS = 23.0  # max cricket ball travel (release → bat)

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

        # Keep only reasonable motion; reject sudden jumps
        if 0 < dist < 200:
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
    miss_count = 0

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

        if chosen is None:
            # Allow brief occlusions without resetting physics history
            miss_count += 1
            continue
        else:
            miss_count = 0

        ball_positions.append((chosen[0], chosen[1], frame_idx))
        prev_center = chosen

    # Final cleanup
    ball_positions = filter_positions(ball_positions)

    cap.release()
    return ball_positions, fps


def compute_swing(ball_positions):
    """
    Simple physics-based swing detection using lateral deviation.
    Returns: 'inswing', 'outswing', or 'none'
    """
    if not ball_positions or len(ball_positions) < 4:
        return {"swing": "none", "confidence": 0.0}

    xs = [p[0] for p in ball_positions]
    ys = [p[1] for p in ball_positions]

    early_x = np.mean(xs[: len(xs)//3])
    late_x = np.mean(xs[-len(xs)//3 :])

    dx = late_x - early_x

    if abs(dx) < 1.2:
        return {"swing": "none", "confidence": 0.0}

    confidence = min(1.0, abs(dx) / 20.0)
    return {
        "swing": "inswing" if dx < 0 else "outswing",
        "confidence": round(confidence, 2)
    }

def compute_spin(ball_positions):
    """
    Motion-based spin inference.
    Returns: 'off spin', 'leg spin', or 'none'
    """
    if not ball_positions or len(ball_positions) < 5:
        return {"spin": "none", "confidence": 0.0}

    xs = [p[0] for p in ball_positions]
    ys = [p[1] for p in ball_positions]

    pitch_idx = int(np.argmax(ys))
    if pitch_idx >= len(xs) - 3:
        return {"spin": "none", "confidence": 0.0}

    post_x = xs[pitch_idx:]
    drift = post_x[-1] - post_x[0]

    if abs(drift) < 0.3:
        return {"spin": "none", "confidence": 0.0}

    confidence = min(1.0, abs(drift) / 6.0)
    return {
        "spin": "off spin" if drift < 0 else "leg spin",
        "confidence": round(confidence, 2)
    }