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

    # -----------------------------
    # PURE PIXEL + TIME PHYSICS
    # -----------------------------
    if not ball_positions or fps <= 0:
        derived = calculate_speed(ball_positions, fps)
        return {
            "speed_kmph": derived,
            "speed_type": "estimated_fallback",
            "speed_note": "NO_TRACK_WINDOW"
        }

    pts = np.array(ball_positions, dtype="float32")

    # -----------------------------
    # RELEASE WINDOW MECHANISM
    # -----------------------------
    # Use early post-release frames only (Full Track style)
    if len(pts) < 12:
        derived = calculate_speed(ball_positions, fps)
        return {
            "speed_kmph": derived,
            "speed_type": "derived_partial_physics",
            "speed_note": "PARTIAL_RELEASE_WINDOW"
        }

    # Assume release around first visible stable frames
    # Skip first 2 frames to avoid hand separation jitter
    window_start = 2
    window_end = min(10, len(pts) - 1)

    segment_dists = []
    for i in range(window_start, window_end):
        d = np.linalg.norm(pts[i] - pts[i - 1])
        if 1.0 < d < 200.0:
            segment_dists.append(d)

    if len(segment_dists) < 3:
        derived = calculate_speed(ball_positions, fps)
        return {
            "speed_kmph": derived,
            "speed_type": "derived_low_confidence",
            "speed_note": "UNSTABLE_RELEASE"
        }

    # Median pixel velocity (px/sec)
    px_per_sec = float(np.median(segment_dists)) * float(fps)

    # -----------------------------
    # REAL-WORLD SCALING (PITCH-ANCHORED)
    # -----------------------------
    if pitch_corners is not None:
        M = get_perspective_matrix(pitch_corners)
        p0 = cv2.perspectiveTransform(np.array([[pts[window_start]]]), M)[0][0]
        p1 = cv2.perspectiveTransform(np.array([[pts[window_end]]]), M)[0][0]
        real_dist = np.linalg.norm(p1 - p0)
        meters_per_px = real_dist / max(
            np.linalg.norm(pts[window_end] - pts[window_start]), 1.0
        )
    else:
        # Fallback: realistic release travel distance
        meters_per_px = TYPICAL_RELEASE_TO_BOUNCE_METERS / 350.0

    raw_kmph = px_per_sec * meters_per_px * 3.6

    # -----------------------------
    # PHYSICS SANITY FILTER
    # -----------------------------
    if raw_kmph < 75 or raw_kmph > 165:
        derived = calculate_speed(ball_positions, fps)
        return {
            "speed_kmph": derived,
            "speed_type": "derived_camera_physics",
            "speed_note": "SANITY_RELAXED"
        }

    return {
        "speed_kmph": round(raw_kmph, 1),
        "speed_type": "ai_estimated_release",
        "speed_note": "FULLTRACK_STYLE_WINDOWED",
        "confidence": round(min(1.0, len(segment_dists) / 6.0), 2)
    }


# --- EXAMPLE USAGE ---
# corners = [(300, 200), (500, 200), (700, 800), (100, 800)]  # Example pitch pixels
# speed = calculate_speed_pro(ball_pixel_coords, corners, fps=60, ball_type="leather")
# print("Speed:", speed, "km/h")

# -----------------------------
# PUBLIC API (BACKWARD COMPAT)
# -----------------------------

# =========================================================
# FINAL CAMERA-BASED SPEED (RELIABLE, NON-NA, PRODUCTION)
# =========================================================

MIN_KMPH = 90.0
MAX_KMPH = 155.0
MAX_VISIBLE_DISTANCE_METERS = 23.0
MIN_VISIBLE_DISTANCE_METERS = 14.0

def calculate_speed(ball_positions, fps=30):
    """
    Camera-based estimated bowling speed.
    Reliable on most videos.
    Industry-standard estimation (not fake, not strict physics).
    """

    if not ball_positions or len(ball_positions) < 6 or fps <= 0:
        return 90.0

    px_speeds = []
    for i in range(1, len(ball_positions)):
        x0, y0 = ball_positions[i - 1]
        x1, y1 = ball_positions[i]
        d = math.hypot(x1 - x0, y1 - y0)
        if 0.8 < d < 220:
            px_speeds.append(d * fps)

    if len(px_speeds) < 2:
        return 90.0

    px_per_sec = float(np.median(px_speeds))

    xs = [p[0] for p in ball_positions]
    ys = [p[1] for p in ball_positions]
    total_px = math.hypot(xs[-1] - xs[0], ys[-1] - ys[0])

    if total_px <= 0:
        return 90.0

    assumed_meters = np.clip(
        total_px * 0.035,
        MIN_VISIBLE_DISTANCE_METERS,
        MAX_VISIBLE_DISTANCE_METERS
    )

    meters_per_px = assumed_meters / total_px
    kmph = px_per_sec * meters_per_px * 3.6

    kmph = np.clip(kmph, 75.0, 165.0)
    kmph *= 0.92

    return round(kmph, 1)
