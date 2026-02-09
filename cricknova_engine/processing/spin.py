import math
import numpy as np

"""
PHYSICS-ONLY SPIN DETECTION (CONSERVATIVE)

Rules:
- Spin is detected ONLY after bounce
- Uses post-bounce lateral deviation vs forward travel
- No arm-action, no seam guess, no scripting
- Returns NO SPIN when evidence is weak
- Names turn direction only when clearly measurable
"""

def _smooth(values, window=3):
    if len(values) < window:
        return values
    out = []
    for i in range(len(values)):
        seg = values[max(0, i - window): min(len(values), i + window + 1)]
        out.append(sum(seg) / len(seg))
    return out

def calculate_spin(ball_positions, fps=30):
    """
    STRICT spin classification.
    Allowed outputs ONLY:
    Straight, Off Spin, Leg Spin
    """

    # Default: Straight (no post-bounce turn)
    result = {
        "name": "Straight"
    }

    # Minimum frames required
    if not ball_positions or len(ball_positions) < 6:
        return result

    # Limit frames for render safety
    if len(ball_positions) > 120:
        ball_positions = ball_positions[:120]

    # --- Bounce detection (max Y = pitch) ---
    ys = np.array([p[1] for p in ball_positions])
    pitch_idx = int(np.argmax(ys))

    # Require frames after bounce
    if pitch_idx < 2 or pitch_idx + 4 >= len(ball_positions):
        return result

    # --- Post-bounce trajectory ---
    post = ball_positions[pitch_idx + 1 : pitch_idx + 16]
    xs = [p[0] for p in post]
    ys = [p[1] for p in post]

    if len(xs) < 5:
        return result

    # Smooth jitter
    xs = _smooth(xs)
    ys = _smooth(ys)

    # Normalize lateral movement
    x0 = xs[0]
    xs_norm = [x - x0 for x in xs]

    lateral_disp = xs_norm[-1] - xs_norm[0]
    forward_disp = ys[-1] - ys[0]

    # Reject unreliable motion
    if abs(forward_disp) < 1.2:
        return result

    # Compute turn angle
    turn_rad = math.atan2(abs(lateral_disp), abs(forward_disp))
    turn_deg = math.degrees(turn_rad)

    # Threshold: below this = Straight
    if turn_deg < 0.12 or abs(lateral_disp) < 0.4:
        return result

    # Direction (batter view convention)
    if lateral_disp < 0:
        result["name"] = "Off Spin"
    else:
        result["name"] = "Leg Spin"

    return result
