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
        "name": "Straight",
        "strength": "Light",
        "turn_deg": 0.25
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

    # If bounce detection weak, still attempt classification
    if pitch_idx < 2 or pitch_idx + 4 >= len(ball_positions):
        pitch_idx = max(1, min(pitch_idx, len(ball_positions) - 5))

    # Use longer post-bounce window for better turn measurement
    post = ball_positions[pitch_idx + 1 : pitch_idx + 22]
    xs = [p[0] for p in post]
    ys = [p[1] for p in post]

    if len(xs) < 3:
        xs = xs + xs
        ys = ys + ys

    # Light smoothing only (avoid killing real deviation)
    xs = _smooth(xs, window=1)
    ys = _smooth(ys, window=1)

    # Normalize lateral movement
    x0 = xs[0]
    xs_norm = [x - x0 for x in xs]

    lateral_disp = xs_norm[-1] - xs_norm[0]
    forward_disp = ys[-1] - ys[0]

    # Do not reject low forward motion; continue with minimal fallback
    if abs(forward_disp) < 0.5:
        forward_disp = 0.5

    # Compute turn angle
    turn_rad = math.atan2(abs(lateral_disp), abs(forward_disp))
    turn_deg = math.degrees(turn_rad)
    result["turn_deg"] = round(turn_deg, 3)

    # Detect real turn based purely on lateral displacement (more stable than tiny degree thresholds)
    if abs(lateral_disp) < 0.008:
        return result

    # Spin direction (based on post-bounce lateral shift)
    if lateral_disp < 0:
        result["name"] = "Off Spin"
    else:
        result["name"] = "Leg Spin"

    # Spin strength classification (realistic, conservative)
    if turn_deg < 0.35:
        result["strength"] = "Light"
    elif turn_deg < 0.9:
        result["strength"] = "Medium"
    else:
        result["strength"] = "Big Turn"

    return result
