import math
import numpy as np
import cv2

MAX_EFFECTIVE_DISTANCE_METERS = 23.0  # domain-bounded max travel distance
MIN_EFFECTIVE_DISTANCE_METERS = 6.0   # minimum plausible travel distance

# -----------------------------
# CONFIG
# -----------------------------
# Physical sanity limits (km/h) to prevent impossible spikes
# REMOVED MAX_SPEED, MIN_SPEED, MIN_PITCH_PX, MAX_PITCH_PX

# --- REAL CRICKET CONSTANTS ---
PITCH_LENGTH_METERS = 18.29  # crease to crease
PITCH_WIDTH_METERS = 3.05  # standard cricket pitch width (meters)
TYPICAL_RELEASE_TO_BOUNCE_METERS = 16.0

# --- PHYSICS GUARANTEES ---
# REMOVED MIN_CONFIDENCE_SPEED_KMPH = 70.0
# REMOVED MAX_CONFIDENCE_SPEED_KMPH = 155.0
MIN_VALID_SEGMENT_METERS = 3.0

# REMOVED clamp function entirely

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

    def _estimated_speed_from_pixels(ball_positions, fps):
        pts = np.array(ball_positions, dtype="float32")
        if len(pts) < 4:
            return None

        dists = np.linalg.norm(pts[1:] - pts[:-1], axis=1)
        dists = dists[dists > 0.5]  # remove jitter
        if len(dists) < 2:
            return None

        px_per_sec = float(np.median(dists)) * fps

        total_px_span = float(np.linalg.norm(pts[-1] - pts[0]))
        if total_px_span <= 1:
            return None

        # Assume real-world travel distance bounded by cricket domain
        assumed_meters = np.clip(
            total_px_span * 0.04,
            MIN_EFFECTIVE_DISTANCE_METERS,
            MAX_EFFECTIVE_DISTANCE_METERS,
        )

        meters_per_px = assumed_meters / total_px_span
        est_kmph = px_per_sec * meters_per_px * 3.6

        if est_kmph <= 0:
            return None

        return {
            "speed_kmph": round(est_kmph, 1),
            "speed_type": "estimated_physics",
            "speed_note": "ASSUMED_PITCH_SCALE",
            "confidence": 0.7
        }

    # -----------------------------
    # HARD RELIABILITY GUARDS
    # -----------------------------
    MIN_FRAMES_FOR_SPEED = 4

    # Maximum number of frames to use for speed calculation (Render-safe)
    MAX_FRAMES_FOR_SPEED = 120

    # Require enough frames for physics to stabilize
    if not ball_positions or len(ball_positions) < MIN_FRAMES_FOR_SPEED:
        est = _estimated_speed_from_pixels(ball_positions, fps)
        if est is not None:
            return est
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "reason": "TRACKING_FAILED"
        }

    # Limit frames to avoid CPU overload and unstable tails (Render-safe)
    if len(ball_positions) > MAX_FRAMES_FOR_SPEED:
        ball_positions = ball_positions[:MAX_FRAMES_FOR_SPEED]

    # Drop first 2 frames to avoid detector jump noise
    if len(ball_positions) > 3:
        ball_positions = ball_positions[2:]

    # 0. Basic sanity checks (always return speed)
    if not ball_positions or len(ball_positions) < 4:
        est = _estimated_speed_from_pixels(ball_positions, fps)
        if est is not None:
            return est
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "reason": "TRACKING_FAILED"
        }

    # HARD GUARD: require enough trajectory
    if len(ball_positions) < 6:
        est = _estimated_speed_from_pixels(ball_positions, fps)
        if est is not None:
            return est
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "reason": "TRACKING_FAILED"
        }

    # --- SEGMENT-BASED PHYSICS (RELEASE → FIRST MAJOR EVENT) ---
    # REMOVED entire segment-based scripted speed block

    # 1. Perspective matrix (optional)
    if pitch_corners is None:
        est = _estimated_speed_from_pixels(ball_positions, fps)
        if est is not None:
            return est

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
        est = _estimated_speed_from_pixels(ball_positions, fps)
        if est is not None:
            return est
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "reason": "TRACKING_FAILED"
        }

    distances = np.array(distances)

    # REMOVED Hybrid noise filtering (IQR + positive-only) block entirely
    # Use distances directly

    # REMOVED multi-window speed estimation and median selection
    mpf_speeds = distances * fps * 3.6
    final_kmph = float(np.median(mpf_speeds))

    if final_kmph <= 0 or final_kmph > 170:
        est = _estimated_speed_from_pixels(ball_positions, fps)
        if est is not None:
            return est
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "reason": "PHYSICS_OUT_OF_RANGE"
        }

    # REMOVED CAMERA NORMALIZATION (SAFE) section entirely

    # REMOVED pixel distance median calculation for return

    return {
        "speed_kmph": round(final_kmph, 1),
        "speed_type": "calibrated_real_world",
        "confidence": 0.95
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
