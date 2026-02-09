import math
import numpy as np

def calculate_spin(ball_positions):
    """
    STRICT spin classification based on REAL post-pitch deviation.
    Allowed outputs ONLY:
    Straight, Off Spin, Leg Spin
    """

    # Default
    result = {"name": "Straight"}

    if not ball_positions or len(ball_positions) < 6:
        return result

    # --- Pitch detection (max Y = bounce) ---
    ys = [p[1] for p in ball_positions]
    pitch_idx = int(np.argmax(ys))

    # Need frames after pitch
    if pitch_idx < 2 or pitch_idx + 4 >= len(ball_positions):
        return result

    # Post-bounce trajectory
    post = ball_positions[pitch_idx + 1 : pitch_idx + 16]
    if len(post) < 5:
        return result

    xs = [p[0] for p in post]
    ys = [p[1] for p in post]

    # Smooth jitter
    xs = np.convolve(xs, np.ones(3)/3, mode="same")
    ys = np.convolve(ys, np.ones(3)/3, mode="same")

    # Normalize lateral movement
    x0 = xs[0]
    xs_norm = xs - x0

    lateral_disp = xs_norm[-1] - xs_norm[0]
    forward_disp = ys[-1] - ys[0]

    # Reject unreliable motion
    if abs(forward_disp) < 1.2:
        return result

    # Turn angle
    turn_rad = math.atan2(abs(lateral_disp), abs(forward_disp))
    turn_deg = math.degrees(turn_rad)

    # Threshold for visible spin
    if turn_deg < 0.12 or abs(lateral_disp) < 0.4:
        return result

    # Direction (RH batter view)
    if lateral_disp < 0:
        result["name"] = "Off Spin"
    else:
        result["name"] = "Leg Spin"

    return result