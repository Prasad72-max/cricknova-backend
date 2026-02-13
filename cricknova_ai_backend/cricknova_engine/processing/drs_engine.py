import numpy as np
import librosa

# Global cache
ball_near_bat_cache = False


def ball_near_bat(trajectory):
    """Bat zone detection"""
    if not trajectory or len(trajectory) < 3:
        return False

    for p in trajectory:
        x, y = p.get("x", 0), p.get("y", 0)
        if 0.45 <= x <= 0.55 and 0.25 <= y <= 0.38:
            return True
    return False


def detect_ultraedge(video_path, trajectory):
    global ball_near_bat_cache

    if not ball_near_bat_cache:
        return False

    try:
        audio, sr = librosa.load(video_path, sr=None, duration=5.0)
    except Exception:
        return False

    frame_len = int(0.008 * sr)
    hop_len = int(0.004 * sr)

    energy = librosa.feature.rms(
        y=audio,
        frame_length=frame_len,
        hop_length=hop_len
    )[0]

    mean_energy = np.mean(energy)
    std_energy = np.std(energy)

    if len(energy) > 10 and np.max(energy) > mean_energy + 8 * std_energy:
        return True

    return False


def detect_stump_hit(trajectory):
    """
    DRS 3.0 – Pure projection-based stump prediction
    """
    if not trajectory or len(trajectory) < 8:
        return 0.0

    recent = trajectory[-8:]

    xs = np.array([p.get("x", 0) for p in recent])
    ys = np.array([p.get("y", 0) for p in recent])

    if len(xs) < 4:
        return 0.0

    try:
        m, c = np.polyfit(ys, xs, 1)
    except Exception:
        return 0.0

    stump_y_plane = 0.78
    projected_x = m * stump_y_plane + c

    stump_center_x = 0.50
    stump_half_width = 0.12

    stump_x_min = stump_center_x - stump_half_width
    stump_x_max = stump_center_x + stump_half_width

    stability = 1 - min(np.std(xs), 0.08)
    stability = max(min(stability, 1.0), 0.4)

    if stump_x_min <= projected_x <= stump_x_max:
        return round(stability, 2)

    return 0.0


def analyze_training(data):
    trajectory = data.get("trajectory", [])
    video_path = data.get("video_path")

    global ball_near_bat_cache
    ball_near_bat_cache = ball_near_bat(trajectory)

    ultraedge = bool(
        video_path and
        ball_near_bat_cache and
        detect_ultraedge(video_path, trajectory)
    )

    stump_confidence = detect_stump_hit(trajectory)

    if ultraedge:
        decision = "NOT OUT"
        reason = "UltraEdge: Bat first contact"
    elif stump_confidence >= 0.70:
        decision = "OUT"
        reason = "Plumb LBW - stumps hit"
    elif stump_confidence >= 0.45:
        decision = "UMPIRE'S CALL"
        reason = "Clipping stumps - marginal"
    else:
        decision = "NOT OUT"
        reason = "Missing stumps outside line"

    return {
        "drs": {
            "ultraedge": ultraedge,
            "stump_confidence": round(stump_confidence, 2),
            "decision": decision,
            "reason": reason,
        }
    }
print("DRS 3.0 ACTIVE")