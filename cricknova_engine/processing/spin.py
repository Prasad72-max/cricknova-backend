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
    empty_result = {
        "type": "none",
        "name": "none",
        "spin_degree": None
    }

    # Render-safe minimum frames (post-bounce physics still enforced)
    if not ball_positions or len(ball_positions) < 4:
        return empty_result

    # Limit frames to stable delivery window (Render-safe)
    if len(ball_positions) > 120:
        ball_positions = ball_positions[:120]

    # --- Bounce detection (max Y = pitch) ---
    ys = np.array([p[1] for p in ball_positions])
    pitch_idx = int(np.argmax(ys))

    # Need stable frames before & after bounce
    if pitch_idx < 2 or pitch_idx + 3 >= len(ball_positions):
        return empty_result

    # --- Collect post-bounce trajectory ---
    post = ball_positions[pitch_idx + 1 : pitch_idx + 14]
    xs = [p[0] for p in post]
    ys = [p[1] for p in post]

    # Require sufficient post-bounce samples
    if len(xs) < 6:
        return empty_result

    # Smooth to reduce tracker jitter
    xs = _smooth(xs)
    ys = _smooth(ys)

    # Normalize lateral movement relative to first post-bounce point
    x0 = xs[0]
    xs_norm = [x - x0 for x in xs]

    lateral_disp = xs_norm[-1] - xs_norm[0]
    forward_disp = ys[-1] - ys[0]

    # Reject near-vertical / unreliable motion
    if abs(forward_disp) < 1.8:
        return empty_result

    # --- Spin angle estimation ---
    turn_rad = math.atan2(abs(lateral_disp), abs(forward_disp))
    turn_deg = math.degrees(turn_rad)

    # Threshold: below this is visually straight after bounce
    if turn_deg < 0.12:
        return empty_result

    # Direction based purely on screen-space deviation
    if abs(lateral_disp) < 0.6:
        return empty_result

    spin_name = "RIGHT TURN SPIN" if lateral_disp > 0 else "LEFT TURN SPIN"

    return {
        "type": "spin",
        "name": spin_name,
        "spin_degree": round(float(turn_deg), 2)
    }
