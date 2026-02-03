import math
import numpy as np
import cv2

...
# -----------------------------
# CONFIG
# -----------------------------
# Physical sanity limits (km/h) to prevent impossible spikes
# REMOVED MAX_SPEED, MIN_SPEED, MIN_PITCH_PX, MAX_PITCH_PX


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
            # HARD motion sanity (px/frame)
            if 1.5 < d < 35.0:
                pixel_dists.append(d)

        if not pixel_dists:
            return {
                "speed_kmph": None,
                "speed_type": "unknown",
                "speed_note": "Unstable pixel motion"
            }

        if len(pixel_dists) < 2:
            return {
                "speed_kmph": None,
                "speed_type": "unknown",
                "speed_note": "Insufficient tracking data"
            }
        else:
            avg_px = np.mean(pixel_dists)
            fps = max(15, fps)
            # Pixel-only fallback (pure physics)
            base = avg_px * fps

        base_kmph = base * 3.6

        if base_kmph <= 0 or math.isnan(base_kmph):
            return {
                "speed_kmph": None,
                "speed_type": "unknown",
                "speed_note": "Invalid pixel physics"
            }

        return {
            "speed_kmph": float(base_kmph),
            "speed_type": "pre-pitch",
            "speed_note": "Pixel-distance / frame-time physics"
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
    avg_mpf = float(np.mean(distances))
    raw_kmph = avg_mpf * fps * 3.6

    # REMOVED soft clamp logic entirely
    final_kmph = raw_kmph

    # -----------------------------
    # CAMERA NORMALIZATION (SAFE)
    # -----------------------------
    # If pitch corners are NOT provided, speed is pixel-based.
    if pitch_corners is None:
        # Pixel-only estimation without real-world calibration
        # Marked as low confidence; no artificial scaling applied
        pass

    if final_kmph <= 0 or math.isnan(final_kmph):
        return {
            "speed_kmph": None,
            "speed_type": "unknown",
            "speed_note": "Physics calculation failed"
        }

    # REMOVED broadcast-style rounding

    return {
        "speed_kmph": float(final_kmph),
        "speed_type": "pre-pitch",
        "speed_note": "Pure pixel + time physics"
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
