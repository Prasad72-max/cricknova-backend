import math
import numpy as np
import cv2


# -----------------------------
# CONFIG
# -----------------------------
MIN_SPEED = 90.0
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

    # 0. Basic sanity checks
    if not ball_positions or len(ball_positions) < 5:
        return 0.0

    # If fps too low, data is too coarse / jittery
    if fps < 25:
        return 0.0

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

    if len(distances) < 3:
        return 0.0

    distances = np.array(distances)

    # 4. Filter Noise (Improved: IQR instead of simple percentiles)
    Q1, Q3 = np.percentile(distances, [25, 75])
    iqr = Q3 - Q1
    lower = Q1 - 1.5 * iqr
    upper = Q3 + 1.5 * iqr
    mask = (distances > lower) & (distances < upper)
    clean_distances = distances[mask]

    if len(clean_distances) < 3:
        return 0.0

    # 5. Estimate initial meters-per-frame for dynamic release window
    median_m_per_frame = np.median(clean_distances)
    if median_m_per_frame <= 0:
        return 0.0

    # Rough speed in m/s using median (just for window sizing)
    estimated_mps = median_m_per_frame * fps

    # Dynamic release window:
    # faster balls will cover more distance per frame, so
    # keep window short but with a minimum frames count.
    # Clamp between 3 and 8 frames after release.
    base_window_seconds = 0.12  # around 0.12s near release
    est_frames_for_window = int(base_window_seconds * fps)
    release_window = max(3, min(8, est_frames_for_window))

    # Use only the first 'release_window' clean distances
    release_distances = clean_distances[:release_window]
    if len(release_distances) == 0:
        return 0.0

    avg_meters_per_frame = np.median(release_distances)

    # 6. Convert to km/h
    mps = avg_meters_per_frame * fps
    raw_kmph = mps * 3.6

    # 7. Realistic Physics Compensation
    # Behind-the-bowler views often miss some vertical component
    angle_correction = 1.04

    # Air resistance / ball type adjustment
    ball_factor_map = {
        "leather": 1.0,
        "tennis": 0.85,
        "rubber": 0.78
    }
    ball_factor = ball_factor_map.get(ball_type.lower(), 1.0)

    final_kmph = raw_kmph * angle_correction * ball_factor

    # 8. Safety Clamps
    # Ignore clearly bogus low speeds
    if final_kmph < MIN_SPEED * 0.8:
        return 0.0

    final_kmph = min(final_kmph, MAX_SPEED)

    # 9. Formatting: int for high speed, 1 decimal for lower
    if final_kmph < 120:
        return round(final_kmph, 1)
    else:
        return int(round(final_kmph))


# --- EXAMPLE USAGE ---
# corners = [(300, 200), (500, 200), (700, 800), (100, 800)]  # Example pitch pixels
# speed = calculate_speed_pro(ball_pixel_coords, corners, fps=60, ball_type="leather")
# print("Speed:", speed, "km/h")
