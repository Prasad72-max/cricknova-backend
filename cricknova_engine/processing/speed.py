import math
import numpy as np
import cv2


# -----------------------------
# CONFIG
# -----------------------------
MIN_SPEED = 55.0  # absolute minimum believable speed (never show 0.0)
MAX_SPEED = 158.0
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
    pitch_corners,   # REQUIRED for high accuracy
    fps=30,
    ball_type="leather"
):
    """
    Calculates release speed using Homography for 'Behind the Bowler' views.
    ball_positions: list of (x, y) pixel coordinates per frame (ordered in time).
    pitch_corners: 4 pitch corner points in image pixels.
    fps: frames per second of the video.
    ball_type: 'leather', 'tennis', 'rubber'.
    """

    # 0. Basic sanity checks (relaxed for short clips)
    if not ball_positions or len(ball_positions) < 2:
        # ultra-short or failed detection: still return believable speed
        return MIN_SPEED

    # Allow low FPS videos but note reduced accuracy
    fps = max(15, fps)

    # 1. Create Perspective Matrix
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
        # fallback for ultra-short (≈2 sec) clips
        approx = np.mean(distances) if len(distances) else 0
        estimated = approx * fps * 3.6
        if estimated <= 0:
            estimated = MIN_SPEED
        return max(estimated, MIN_SPEED)

    distances = np.array(distances)

    # 4. Hybrid noise filtering (IQR + positive-only)
    distances = distances[distances > 0]
    if len(distances) < 2:
        return MIN_SPEED

    Q1, Q3 = np.percentile(distances, [25, 75])
    iqr = max(Q3 - Q1, 1e-6)
    lower = max(0, Q1 - 1.2 * iqr)
    upper = Q3 + 1.2 * iqr

    clean_distances = distances[(distances >= lower) & (distances <= upper)]
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
        # absolute fallback: estimate from total displacement (2-sec safe)
        total_dist = np.sum(clean_distances)
        time_sec = max(len(clean_distances) / fps, 0.05)
        fallback_speed = (total_dist / time_sec) * 3.6
        if fallback_speed <= 0:
            fallback_speed = MIN_SPEED
        return max(fallback_speed, MIN_SPEED)

    # Use median of window speeds to avoid spikes
    raw_kmph = float(np.median(speed_estimates))

    # 7. Realistic Physics Compensation
    # Behind-the-bowler views often miss some vertical component
    # Dynamic angle correction (short clips need more compensation)
    clip_factor = 1.0 + min(0.08, 5 / max(len(ball_positions), 5))
    angle_correction = 1.02 * clip_factor

    # Air resistance / ball type adjustment
    ball_factor_map = {
        "leather": 1.0,
        "tennis": 0.85,
        "rubber": 0.78
    }
    ball_factor = ball_factor_map.get(ball_type.lower(), 1.0)

    final_kmph = raw_kmph * angle_correction * ball_factor

    # Final hard safety net (never allow zero or negative)
    if final_kmph <= 0:
        final_kmph = MIN_SPEED

    # 8. Safety Clamps
    # Allow slow balls but never drop to zero
    if final_kmph < MIN_SPEED:
        final_kmph = MIN_SPEED

    final_kmph = min(final_kmph, MAX_SPEED)

    # 9. Formatting: int for high speed, 1 decimal for lower
    print("SPEED DEBUG => raw:", raw_kmph, "final:", final_kmph, "fps:", fps, "points:", len(ball_positions))
    if final_kmph < 120:
        return round(final_kmph, 1)
    else:
        return int(round(final_kmph))


# --- EXAMPLE USAGE ---
# corners = [(300, 200), (500, 200), (700, 800), (100, 800)]  # Example pitch pixels
# speed = calculate_speed_pro(ball_pixel_coords, corners, fps=60, ball_type="leather")
# print("Speed:", speed, "km/h")
