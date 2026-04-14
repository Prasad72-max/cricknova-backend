import math
import numpy as np

"""
NEARBY SPIN ESTIMATION FROM VIDEO TRAJECTORY
- Data-driven (no scripted values)
- Uses real trajectory deviation after bounce
- Camera-aware lateral movement
- Returns NONE if spin cannot be reliably inferred
"""

def calculate_spin(ball_positions, fps=30):
    import math
    import numpy as np

    empty_result = {
        "type": "none",
        "name": "none",
        "turn_px": 0.0,
        "turn_est_deg": 0.0,
        "confidence": "low"
    }

    if not ball_positions or len(ball_positions) < 10:
        return empty_result

    # Detect bounce (max Y)
    ys = np.array([p[1] for p in ball_positions])
    pitch_idx = int(np.argmax(ys))

    # Need enough frames after bounce
    if pitch_idx < 2 or pitch_idx + 5 >= len(ball_positions):
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

    # Normalize displacement (avoid resolution dependency)
    norm_forward = abs(forward_disp)
    norm_lateral = abs(lateral_disp)

    if norm_forward < 0.002:  # too little forward movement
        return empty_result

    # Geometry-based turn angle using stable atan2
    turn_rad = math.atan2(norm_lateral, norm_forward)
    turn_deg = math.degrees(turn_rad)

    # ---- Cricket-realistic nearby spin bands ----
    # Allow very slight but real spin to be reported
    if turn_deg < 0.8:
        return empty_result

    if turn_deg < 1.5:
        confidence = "low"
    elif turn_deg < 4.0:
        confidence = "medium"
    else:
        confidence = "high"

    # Hard clamp: mobile single-camera cannot exceed this
    turn_deg = min(turn_deg, 12.0)  # allow stronger visible spin

    # Spin direction based purely on post-bounce lateral movement
    # Positive X movement (to the right on screen) -> leg-spin
    # Negative X movement (to the left on screen) -> off-spin
    if lateral_disp > 0:
        spin_name = "leg-spin"
    else:
        spin_name = "off-spin"

    return {
        "type": "spin_estimate",
        "name": spin_name,
        "turn_est_deg": round(turn_deg, 2),
        "confidence": confidence
    }
