import math
import numpy as np

def calculate_spin(ball_positions):
    """
    REAL spin classification based on accumulated post-pitch lateral curvature.
    Outputs:
    Straight / Off Spin / Leg Spin
    """

    result = {"name": None}

    if not ball_positions or len(ball_positions) < 8:
        return {"name": "Straight"}

    # Detect pitch (max Y)
    ys = [p[1] for p in ball_positions]
    pitch_idx = int(np.argmax(ys))

    # Require sufficient post-pitch frames
    post = ball_positions[pitch_idx + 1 : pitch_idx + 20]
    if len(post) < 6:
        return {"name": "Straight"}

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
        return {"name": "Straight"}

    # Accumulate lateral curvature
    lateral_curve = np.sum(dx)
    # --- CAMERA MIRROR FIX ---
    # Flip horizontal axis to correct mirrored videos
    lateral_curve *= -1

    # Compute curvature ratio
    curvature_ratio = abs(lateral_curve) / (abs(forward_motion) + 1e-6)

    # Ignore very small deviation (reduce false straight / false spin)
    if curvature_ratio < 0.02:
        return {"name": "Straight"}

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

    result = {"name": None}

    if not ball_positions or len(ball_positions) < 8:
        return {"name": "Straight"}

    # Detect pitch (max Y)
    ys = [p[1] for p in ball_positions]
    pitch_idx = int(np.argmax(ys))

    # Use ONLY pre-pitch frames (real swing happens in air)
    pre = ball_positions[max(0, pitch_idx - 15): pitch_idx]
    if len(pre) < 6:
        return {"name": "Straight"}

    xs = np.array([p[0] for p in pre], dtype=float)
    ys = np.array([p[1] for p in pre], dtype=float)

    # Light smoothing (very minimal, preserve real deviation)
    if len(xs) >= 5:
        kernel = np.ones(3) / 3
        xs = np.convolve(xs, kernel, mode="same")
        ys = np.convolve(ys, kernel, mode="same")

    # Measure total lateral shift in air (before bounce)
    lateral_shift = xs[-1] - xs[0]
    forward_travel = ys[-1] - ys[0]

    # Require real forward movement
    if abs(forward_travel) < 1.0:
        return {"name": "Straight"}

    # --- CAMERA MIRROR FIX ---
    lateral_shift *= -1

    # Detect real swing using absolute lateral displacement
    if abs(lateral_shift) < 0.01:
        return {"name": "Straight"}

    # Direction logic (relative to batter)
    if batter_hand == "RH":
        if lateral_shift < 0:
            return {"name": "In Swing"}
        else:
            return {"name": "Out Swing"}
    else:
        if lateral_shift < 0:
            return {"name": "Out Swing"}
        else:
            return {"name": "In Swing"}