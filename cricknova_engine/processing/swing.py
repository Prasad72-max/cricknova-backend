import math
import numpy as np

def calculate_spin(ball_positions):
    """
    REAL spin classification based on accumulated post-pitch lateral curvature.
    Outputs:
    Straight / Off Spin / Leg Spin
    """

    result = {"name": "Straight"}

    if not ball_positions or len(ball_positions) < 8:
        return result

    # Detect pitch (max Y)
    ys = [p[1] for p in ball_positions]
    pitch_idx = int(np.argmax(ys))

    # Require sufficient post-pitch frames
    post = ball_positions[pitch_idx + 1 : pitch_idx + 20]
    if len(post) < 6:
        return result

    xs = np.array([p[0] for p in post], dtype=float)
    ys = np.array([p[1] for p in post], dtype=float)

    # Smooth jitter lightly (do NOT over-smooth)
    if len(xs) >= 5:
        kernel = np.ones(3) / 3
        xs = np.convolve(xs, kernel, mode="same")
        ys = np.convolve(ys, kernel, mode="same")

    # Compute frame-to-frame deltas
    dx = np.diff(xs)
    dy = np.diff(ys)

    # Reject if no forward motion
    forward_motion = np.sum(dy)
    if abs(forward_motion) < 0.8:
        return result

    # Accumulate lateral curvature
    lateral_curve = np.sum(dx)
    # --- CAMERA MIRROR FIX ---
    # Flip horizontal axis to correct mirrored videos
    lateral_curve *= -1

    # Sensitive but real-world threshold (normalized coordinates)
    dynamic_spin_threshold = max(0.01, abs(forward_motion) * 0.01)

    if abs(lateral_curve) < dynamic_spin_threshold:
        return result

    # Direction (RH batter reference)
    if lateral_curve < 0:
        result["name"] = "Off Spin"
    else:
        result["name"] = "Leg Spin"

    return result

def calculate_swing(ball_positions, batter_hand="RH"):
    """
    REAL swing detection based on pre-pitch lateral curvature.
    Detects: Straight / Inswing / Outswing

    batter_hand: "RH" or "LH"
    """

    result = {"name": "Straight"}

    if not ball_positions or len(ball_positions) < 8:
        return result

    # Detect pitch (max Y)
    ys = [p[1] for p in ball_positions]
    pitch_idx = int(np.argmax(ys))

    # Use ONLY pre-pitch frames (real swing happens in air)
    pre = ball_positions[max(0, pitch_idx - 15): pitch_idx]
    if len(pre) < 6:
        return result

    xs = np.array([p[0] for p in pre], dtype=float)
    ys = np.array([p[1] for p in pre], dtype=float)

    # Light smoothing to remove tracking noise (no overfitting)
    if len(xs) >= 5:
        kernel = np.ones(3) / 3
        xs = np.convolve(xs, kernel, mode="same")
        ys = np.convolve(ys, kernel, mode="same")

    # Frame-to-frame motion
    dx = np.diff(xs)
    dy = np.diff(ys)

    # Ensure forward travel
    forward_motion = np.sum(dy)
    if abs(forward_motion) < 1.0:
        return result

    # Accumulate lateral air movement
    lateral_air_curve = np.sum(dx)
    # --- CAMERA MIRROR FIX ---
    # Flip horizontal axis to correct mirrored videos
    lateral_air_curve *= -1

    # Dynamic swing sensitivity (works for normalized 0–1 scale)
    dynamic_swing_threshold = max(0.008, abs(forward_motion) * 0.012)

    if abs(lateral_air_curve) < dynamic_swing_threshold:
        return result

    # Direction logic (relative to batter) — FIXED SIGN
    if batter_hand == "RH":
        if lateral_air_curve < 0:
            result["name"] = "In Swing"
        else:
            result["name"] = "Out Swing"
    else:
        if lateral_air_curve < 0:
            result["name"] = "Out Swing"
        else:
            result["name"] = "In Swing"

    return result