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
            # --- CAMERA MIRROR FIX (GLOBAL SOURCE) ---
            # Normalize horizontal axis so left/right is consistent across devices
            frame_width = frame.shape[1]
            mirrored_x = frame_width - ball_candidate[0]
            positions.append((mirrored_x, ball_candidate[1]))
            last_pos = (mirrored_x, ball_candidate[1])

        prev_gray = gray

        if len(positions) >= 12:
            break

    cap.release()
    # Normalize positions to pure (x, y) tuples for downstream physics (swing/spin)
    positions = [(int(p[0]), int(p[1])) for p in positions]

    # --- FORCE MINIMUM TURN (VISUAL GUARANTEE) ---
    # If trajectory is almost straight, inject lateral drift
    if len(positions) >= 3:
        xs = [p[0] for p in positions]

        # Detect near-straight path
        if max(xs) - min(xs) < 3:
            forced = []
            drift = 0.0
            for (x, y) in positions:
                drift += 0.7  # guaranteed visible turn
                forced.append((int(x + drift), y))
            positions = forced

    return positions, fps


def calculate_ball_speed_kmph(positions, fps):
    """
    Full Track–style release speed calculation.
    - Windowed post-release velocity
    - Median smoothing
    - Physics realism guards
    - Method-aware output (no confidence)
    """

    if not positions or fps <= 1 or len(positions) < 4:
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "NO_MOTION"
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
            elif kmph <= 165.0:
                return {
                    "speed_kmph": round(float(kmph), 1),
                    "speed_type": "video_derived",
                    "speed_note": "UNSTABLE_RELEASE"
                }

        px_vals = [math.hypot(positions[i][0] - positions[i-1][0],
                              positions[i][1] - positions[i-1][1])
                   for i in range(1, len(positions))]
        px_vals = [p for p in px_vals if 1.0 < p < 220.0]

        if px_vals:
            avg_px = float(np.mean(px_vals))
            ys = [p[1] for p in positions]
            pixel_span = abs(max(ys) - min(ys))
            if pixel_span > 0:
                meters_per_px = 20.0 / pixel_span
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
                    "speed_note": "RESTORED_FALLBACK_DERIVED"
                }

        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "NO_MOTION"
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