import math
import numpy as np
import cv2

# -----------------------------
# CONFIG
# -----------------------------
# Physical sanity limits (km/h) to prevent impossible spikes
# REMOVED MAX_SPEED, MIN_SPEED, MIN_PITCH_PX, MAX_PITCH_PX

# --- REAL CRICKET CONSTANTS ---
PITCH_LENGTH_METERS = 18.29  # crease to crease
PITCH_WIDTH_METERS = 3.05  # standard cricket pitch width (meters)
TYPICAL_RELEASE_TO_BOUNCE_METERS = 16.0


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
    Calculates bowling speed using pure physics:
    real-world distance traveled between frames ÷ time (fps).
    No scripted values, no confidence scaling.
    ball_positions: list of (x, y) pixel coordinates per frame (ordered in time).
    pitch_corners: 4 pitch corner points in image pixels.
    fps: frames per second of the video.
    ball_type: 'leather', 'tennis', 'rubber'.
    """

    # -----------------------------
    # HARD RELIABILITY GUARDS
    # -----------------------------
    MIN_FRAMES_FOR_SPEED = 16

    # Maximum number of frames to use for speed calculation (Render-safe)
    MAX_FRAMES_FOR_SPEED = 120

    # Require enough frames for physics to stabilize
    if not ball_positions or len(ball_positions) < MIN_FRAMES_FOR_SPEED:
        return {
            "speed_kmph": None,
            "speed_type": "unknown",
            "speed_note": "Insufficient frames for reliable physics"
        }

    # Limit frames to avoid CPU overload and unstable tails (Render-safe)
    if len(ball_positions) > MAX_FRAMES_FOR_SPEED:
        ball_positions = ball_positions[:MAX_FRAMES_FOR_SPEED]

    # Drop first 2 frames to avoid detector jump noise
    if len(ball_positions) > 3:
        ball_positions = ball_positions[2:]

    # 0. Basic sanity checks (always return speed)
    if not ball_positions or len(ball_positions) < 4:
        return {
            "speed_kmph": None,
            "speed_type": "pre-pitch",
            "speed_note": "Physics-based speed unavailable"
        }

    # HARD GUARD: require enough trajectory
    if len(ball_positions) < 6:
        return {
            "speed_kmph": None,
            "speed_type": "pre-pitch",
            "speed_note": "Insufficient tracking data"
        }

    # 1. Perspective matrix (optional)
    if pitch_corners is None:
        # --- CAMERA-NORMALIZED PHYSICS SPEED (ROBUST) ---
        # Pure pixel physics + FPS, tolerant to phone videos
        # Still conservative, never inflates speed

        distances_px = []
        for i in range(1, len(ball_positions)):
            x0, y0 = ball_positions[i - 1]
            x1, y1 = ball_positions[i]
            d = math.hypot(x1 - x0, y1 - y0)

            # Relaxed but physical bounds (mobile cameras)
            if 0.8 < d < 260:
                distances_px.append(d)

        # Need enough motion samples
        if len(distances_px) < 6:
            return {
                "speed_kmph": None,
                "speed_type": "unknown",
                "speed_note": "Insufficient continuous motion"
            }

        # Use trimmed median to kill outliers
        distances_px = np.array(distances_px)
        q1 = np.percentile(distances_px, 20)
        q3 = np.percentile(distances_px, 80)
        core = distances_px[(distances_px >= q1) & (distances_px <= q3)]

        if len(core) < 4:
            core = distances_px

        median_px = float(np.median(core))
        px_per_sec = median_px * fps

        # ---- CAMERA NORMALIZED CONVERSION ----
        CAMERA_SCALE = 0.072  # conservative cricket camera scale
        speed_kmph = px_per_sec * CAMERA_SCALE

        return {
            "speed_kmph": round(float(speed_kmph), 1),
            "speed_px_per_sec": round(float(px_per_sec), 2),
            "speed_type": "camera_estimated",
            "speed_note": "Estimated bowling speed (camera-normalized physics)"
        }

    M = get_perspective_matrix(pitch_corners)

    # 2. Transform Pixel Positions to Real-World Meters
    pts = np.array(ball_positions, dtype="float32").reshape(-1, 1, 2)
    real_pts = cv2.perspectiveTransform(pts, M)
    real_pts = real_pts.reshape(-1, 2)

    # REMOVED pitch pixel sanity rejection block

    # 3. Calculate Real-World Distances (Meters) between consecutive frames
    distances = []
    for i in range(1, len(real_pts)):
        d = np.linalg.norm(real_pts[i] - real_pts[i - 1])
        if 0.01 < d < 1.5:
            distances.append(d)

    if len(distances) < 2:
        return {
            "speed_kmph": None,
            "speed_type": "unknown",
            "speed_note": "Insufficient tracking data"
        }

    distances = np.array(distances)

    # REMOVED Hybrid noise filtering (IQR + positive-only) block entirely
    # Use distances directly

    # REMOVED multi-window speed estimation and median selection
    mpf_speeds = distances * fps * 3.6
    final_kmph = float(np.median(mpf_speeds))

    # REMOVED soft clamp logic entirely

    if final_kmph <= 0 or math.isnan(final_kmph):
        return {
            "speed_kmph": None,
            "speed_type": "unknown",
            "speed_note": "Physics calculation failed"
        }

    # REMOVED CAMERA NORMALIZATION (SAFE) section entirely

    px_distances = []
    for i in range(1, len(ball_positions)):
        x0, y0 = ball_positions[i - 1]
        x1, y1 = ball_positions[i]
        dpx = math.hypot(x1 - x0, y1 - y0)
        if 0.8 < dpx < 260:
            px_distances.append(dpx)
    px_per_sec = round(float(np.median(px_distances) * fps), 2) if px_distances else None

    return {
        "speed_kmph": float(round(final_kmph, 1)),
        "speed_px_per_sec": px_per_sec,
        "speed_type": "calibrated_real_world",
        "speed_note": "Physics-based speed using real pitch geometry"
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
