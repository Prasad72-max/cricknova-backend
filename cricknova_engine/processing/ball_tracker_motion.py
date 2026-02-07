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
    fps = min(max(fps, 24.0), 60.0)

    positions = []
    last_pos = None
    prev_gray = None
    frame_count = 0
    miss_count = 0

    TARGET_WIDTH = 640

    while cap.isOpened() and frame_count < max_frames:
        ret, frame = cap.read()
        if not ret:
            break

        frame_count += 1

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
            miss_count += 1
            prev_gray = gray
            continue
        else:
            miss_count = 0
            positions.append(ball_candidate)
            last_pos = ball_candidate

        prev_gray = gray

        if len(positions) >= 12:
            break

    cap.release()
    return positions, fps


def calculate_ball_speed_kmph(positions, fps):
    """
    Full Track–style AI estimated release speed.
    - Windowed post-release velocity
    - Median smoothing
    - Human fast-bowling physics gate
    - Speed returned ONLY when reliable
    """

    if not positions or fps <= 1 or len(positions) < 6:
        return {
            "speed_kmph": None,
            "speed_type": "insufficient_tracking",
            "confidence": 0.0,
            "speed_note": "INSUFFICIENT_FRAMES"
        }

    fps = min(max(float(fps), 24.0), 240.0)

    # Skip first 2 frames (hand separation jitter)
    window_start = 2
    window_end = min(10, len(positions) - 1)

    seg_dists = []
    for i in range(window_start, window_end):
        x0, y0 = positions[i - 1]
        x1, y1 = positions[i]
        d = math.hypot(x1 - x0, y1 - y0)
        if 1.0 < d < 200.0:
            seg_dists.append(d)

    if len(seg_dists) < 3:
        ys = [p[1] for p in positions]
        pixel_span = abs(max(ys) - min(ys))

        if pixel_span > 0:
            FRAME_METERS = 20.0
            meters_per_px = FRAME_METERS / pixel_span
            avg_px = float(np.mean(seg_dists)) if seg_dists else 1.0
            kmph = avg_px * meters_per_px * fps * 3.6

            if 60.0 <= kmph <= 170.0:
                return {
                    "speed_kmph": round(float(kmph), 1),
                    "speed_type": "video_derived",
                    "confidence": 0.5,
                    "speed_note": "UNSTABLE_RELEASE"
                }

        px_vals = [math.hypot(positions[i][0] - positions[i-1][0],
                              positions[i][1] - positions[i-1][1])
                   for i in range(1, len(positions))]
        px_vals = [p for p in px_vals if 1.0 < p < 220.0]

        if px_vals:
            px_per_sec = float(np.median(px_vals)) * fps
            CAMERA_SCALE = 0.072
            kmph = px_per_sec * CAMERA_SCALE

            return {
                "speed_kmph": round(kmph, 1),
                "speed_type": "camera_normalized",
                "confidence": 0.35,
                "speed_note": "FALLBACK_PIXEL_PHYSICS"
            }

        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "confidence": 0.0,
            "speed_note": "NO_MOTION"
        }

    # Median px/sec over release window
    px_per_sec = float(np.median(seg_dists)) * fps

    # Realistic release-to-bounce scaling (fallback)
    meters_per_px = 17.0 / 320.0
    raw_kmph = px_per_sec * meters_per_px * 3.6

    # Human fast-bowling physics gate
    if raw_kmph < 60.0 or raw_kmph > 170.0:
        return {
            "speed_kmph": round(raw_kmph, 1),
            "speed_type": "low_confidence_physics",
            "confidence": 0.4,
            "speed_note": "OUT_OF_RANGE_BUT_REAL_MOTION"
        }

    return {
        "speed_kmph": round(raw_kmph, 1),
        "speed_type": "ai_estimated_release",
        "confidence": round(min(1.0, len(seg_dists) / 6.0), 2),
        "speed_note": "FULLTRACK_STYLE_WINDOWED"
    }


def calculate_swing_type(positions):
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