import math
import numpy as np
import cv2

...
# -----------------------------
# CONFIG
# -----------------------------
# No hard speed clamps – physics decides
MAX_SPEED = None
MIN_SPEED = None
PITCH_LENGTH_METERS = 20.12
PITCH_WIDTH_METERS = 3.05


def get_perspective_matrix(pitch_corners):
    """
    pitch_corners: List of 4 (x,y) tuples:
    [top_left, top_right, bottom_right, bottom_left]
    where 'top' is near the batsman and 'bottom' is near the bowler.
    """
    src = np.float32(pitch_corners)
    # Mapping to a real-world rectangle (meters)
    dst = np.float32([
        [0, 0],
        [PITCH_WIDTH_METERS, 0],
        [PITCH_WIDTH_METERS, PITCH_LENGTH_METERS],
        [0, PITCH_LENGTH_METERS]
    ])
    return cv2.getPerspectiveTransform(src, dst)


def calculate_speed_pro(
    ball_positions,
    pitch_corners=None,   # OPTIONAL now
    fps=30,
    ball_type="leather"
):
    """
    Calculates release speed from frame-to-frame distance over time.
    Returns speed only (pure physics).
    ball_positions: list of (x, y) pixel coordinates per frame (ordered in time).
    pitch_corners: 4 pitch corner points in image pixels.
    fps: frames per second of the video.
    ball_type: 'leather', 'tennis', 'rubber'.
    """

    # 0. Basic sanity checks (always return speed)
    if not ball_positions or len(ball_positions) < 4:
        return {
            "speed_kmph": None,
            "speed_type": "unknown",
            "speed_note": "Insufficient tracking data"
        }

    # Allow low FPS videos but note reduced accuracy
    fps = max(15, fps)

    # 1. Perspective matrix (optional)
    if pitch_corners is None:
        # Fallback: pixel-distance based estimation
        pixel_dists = []
        for i in range(1, len(ball_positions)):
            d = np.linalg.norm(
                np.array(ball_positions[i]) - np.array(ball_positions[i - 1])
            )
            if d > 0:
                pixel_dists.append(d)

        if len(pixel_dists) < 2:
            return {
                "speed_kmph": None,
                "speed_type": "unknown",
                "speed_note": "Insufficient tracking data"
            }
        else:
            avg_px = np.mean(pixel_dists)
            fps = max(15, fps)
            # Pixel-only fallback (low confidence)
            base = avg_px * fps

        return {
            "speed_kmph": round(float(base), 1),
            "speed_type": "pre-pitch",
            "speed_note": "Pixel-only speed"
        }

    M = get_perspective_matrix(pitch_corners)

    # 2. Transform Pixel Positions to Real-World Meters
    pts = np.array(ball_positions, dtype="float32").reshape(-1, 1, 2)
    real_pts = cv2.perspectiveTransform(pts, M)
    real_pts = real_pts.reshape(-1, 2)

    # 3. Calculate Real-World Distances (Meters) between consecutive frames
    distances = []
    for i in range(1, len(real_pts)):
        d = np.linalg.norm(real_pts[i] - real_pts[i - 1])
        distances.append(d)

    if len(distances) < 2:
        return {
            "speed_kmph": None,
            "speed_type": "unknown",
            "speed_note": "Insufficient tracking data"
        }

    distances = np.array(distances)

    # 4. Hybrid noise filtering (IQR + positive-only)
    distances = distances[distances > 0]
    if len(distances) < 2:
        return {
            "speed_kmph": None,
            "speed_type": "unknown",
            "speed_note": "Insufficient tracking data"
        }

    Q1, Q3 = np.percentile(distances, [25, 75])
    iqr = max(Q3 - Q1, 1e-6)
    lower = max(0, Q1 - 1.2 * iqr)
    upper = Q3 + 1.2 * iqr

    clean_distances = distances[(distances >= lower) & (distances <= upper)]
    # Removed confidence calculation line here

    if len(clean_distances) < 2:
        clean_distances = distances

    # 5. Multi-window speed estimation (robust for all clip lengths)
    window_sizes = [min(3, len(clean_distances)),
                    min(5, len(clean_distances)),
                    min(8, len(clean_distances))]

    speed_estimates = []
    for w in window_sizes:
        if w < 2:
            continue
        segment = clean_distances[:w]
        avg_mpf = np.mean(segment)
        if avg_mpf > 0:
            speed_estimates.append(avg_mpf * fps * 3.6)

    if not speed_estimates:
        return {
            "speed_kmph": None,
            "speed_type": "unknown",
            "speed_note": "Insufficient tracking data"
        }

    # Use median of window speeds to avoid spikes
    raw_kmph = float(np.median(speed_estimates))

    # Pure physics: distance / time only
    final_kmph = raw_kmph


    if final_kmph <= 0 or math.isnan(final_kmph):
        return {
            "speed_kmph": None,
            "speed_type": "unknown",
            "speed_note": "Insufficient tracking data"
        }

    print("SPEED PHYSICS => raw:", raw_kmph, "final:", final_kmph, "fps:", fps, "points:", len(ball_positions))

    # Broadcast-style rounding (natural, not perfect)
    final_kmph = round(float(final_kmph), 1)

    return {
        "speed_kmph": final_kmph,
        "speed_type": "pre-pitch",
        "speed_note": "Frame-distance physics speed"
    }


# --- EXAMPLE USAGE ---
# corners = [(300, 200), (500, 200), (700, 800), (100, 800)]  # Example pitch pixels
# speed = calculate_speed_pro(ball_pixel_coords, corners, fps=60, ball_type="leather")
# print("Speed:", speed, "km/h")

# -----------------------------
# PUBLIC API (BACKWARD COMPAT)
# -----------------------------
def calculate_speed(ball_positions, fps=30, pitch_corners=None, ball_type="leather"):
    """
    Backward-compatible wrapper expected by backend.
    Calls calculate_speed_pro internally.
    """
    return calculate_speed_pro(
        ball_positions=ball_positions,
        pitch_corners=pitch_corners,
        fps=fps,
        ball_type=ball_type
    )
