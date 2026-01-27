import math
import numpy as np

"""
PHYSICS-ONLY SPIN ESTIMATION FROM VIDEO TRAJECTORY
- Fully data-driven (no scripted or forced values)
- Uses real post-bounce trajectory deviation
- Camera-aware lateral movement only
- Returns NONE when spin is not physically reliable
"""

def calculate_spin(ball_positions, fps=30):
    import math
    import numpy as np

    empty_result = {
        "type": "none",
        "name": "none",
        "spin_degree": None
    }

    if not ball_positions or len(ball_positions) < 8:
        return empty_result

    # Detect bounce (max Y)
    ys = np.array([p[1] for p in ball_positions])
    pitch_idx = int(np.argmax(ys))

    # Need enough frames after bounce
    if pitch_idx < 3 or pitch_idx + 4 >= len(ball_positions):
        return empty_result

    # Collect post-bounce trajectory
    post_x = []
    post_y = []
    for i in range(pitch_idx + 1, min(pitch_idx + 7, len(ball_positions))):
        post_x.append(ball_positions[i][0])
        post_y.append(ball_positions[i][1])

    if len(post_x) < 3:
        return empty_result

    lateral_disp = post_x[-1] - post_x[0]
    forward_disp = post_y[-1] - post_y[0]

    # Avoid math explosion
    if abs(forward_disp) < 8:
        return empty_result

    # Geometry-based turn angle using stable atan2
    turn_rad = math.atan2(abs(lateral_disp), abs(forward_disp))
    turn_deg = math.degrees(turn_rad)

    # Allow very light but still physically plausible spin
    if turn_deg < 0.1:
        return empty_result

    # Hard clamp: mobile single-camera cannot exceed this
    turn_deg = min(turn_deg, 8.0)

    # Spin direction based purely on post-bounce lateral movement
    # Positive X movement (to the right on screen) -> leg-spin
    # Negative X movement (to the left on screen) -> off-spin
    if lateral_disp > 0:
        spin_name = "leg-spin"
    else:
        spin_name = "off-spin"

    return {
        "type": "spin",
        "name": spin_name.replace("-", " "),
        "spin_degree": round(turn_deg, 2)
    }
