import cv2 as cv
import numpy as np
import math

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


# --- Physics-based speed calculator ---
def compute_speed_kmph(ball_positions, fps):
    """
    Full Track–style release speed calculation.
    - Windowed post-release velocity
    - Median-based smoothing
    - Physics realism guards
    - Method-aware output (no confidence)
    """

    if not ball_positions or fps <= 1 or len(ball_positions) < 3:
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "INSUFFICIENT_TRACK_POINTS"
        }

    fps = min(max(fps, 24), 240)

    # Extract positions only
    pts = [(p[0], p[1]) for p in ball_positions]

    # Skip first 2 frames (hand separation jitter)
    window_start = 2
    window_end = min(10, len(pts) - 1)

    seg_dists = []
    for i in range(window_start, window_end):
        d = math.hypot(
            pts[i][0] - pts[i - 1][0],
            pts[i][1] - pts[i - 1][1]
        )
        if 1.0 < d < 200.0:
            seg_dists.append(d)

    if len(seg_dists) < 3:
        # Conservative video-based fallback
        ys = [p[1] for p in ball_positions]
        pixel_span = abs(max(ys) - min(ys))

        if pixel_span > 0:
            FRAME_METERS = 20.0
            meters_per_px = FRAME_METERS / pixel_span
            avg_px = float(np.mean(seg_dists)) if seg_dists else 1.0
            kmph = avg_px * meters_per_px * fps * 3.6

            if kmph < 40.0:
                return {
                    "speed_kmph": None,
                    "speed_type": "too_slow",
                    "speed_note": "NON_BOWLING_OR_TRACKING_NOISE"
                }
            elif kmph < 55.0:
                return {
                    "speed_kmph": round(float(kmph), 1),
                    "speed_type": "very_slow_estimate",
                    "speed_note": "BORDERLINE_LOW_SPEED"
                }

            kmph = min(kmph, 165.0)
            return {
                "speed_kmph": round(float(kmph), 1),
                "speed_type": "video_derived",
                "speed_note": "PARTIAL_TRACK_PHYSICS"
            }

        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "INSUFFICIENT_PIXEL_SPAN"
        }

    # Median px/sec over release window
    px_per_sec = float(np.median(seg_dists)) * fps

    # Realistic release-to-bounce scaling (fallback)
    meters_per_px = 17.0 / 320.0
    raw_kmph = px_per_sec * meters_per_px * 3.6

    # LOW SPEED REALISM GUARD
    if raw_kmph < 40.0:
        return {
            "speed_kmph": None,
            "speed_type": "too_slow",
            "speed_note": "NON_BOWLING_OR_TRACKING_NOISE"
        }
    elif raw_kmph < 55.0:
        return {
            "speed_kmph": round(float(raw_kmph), 1),
            "speed_type": "very_slow_estimate",
            "speed_note": "BORDERLINE_LOW_SPEED"
        }
    elif raw_kmph > 165.0:
        return {
            "speed_kmph": round(165.0, 1),
            "speed_type": "derived_physics",
            "speed_note": "HIGH_SPEED_SANITY_FALLBACK"
        }

    return {
        "speed_kmph": round(raw_kmph, 1),
        "speed_type": "measured_release",
        "speed_note": "FULLTRACK_STYLE_WINDOWED"
    }

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

# --- Public speed API (restore compatibility) ---
def calculate_ball_speed_kmph(ball_positions, fps):
    """
    Public API wrapper expected by backend.
    Delegates to compute_speed_kmph.
    """
    return compute_speed_kmph(ball_positions, fps)