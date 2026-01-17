import numpy as np
import librosa


def ball_near_bat(trajectory):
    """
    Returns True only if ball passes through bat zone.
    This prevents UltraEdge firing when bat is nowhere near.
    """
    if not trajectory:
        return False

    # Conservative bat zone (screen-normalized)
    # Bat usually around middle-lower region
    for p in trajectory:
        x = p.get("x", 0)
        y = p.get("y", 0)

        # Bat zone window
        if 0.40 <= x <= 0.60 and 0.20 <= y <= 0.45:
            return True

    return False


# -----------------------------
# ULTRAEDGE
# -----------------------------
def detect_ultraedge(video_path):
    # If ball never came near bat, UltraEdge is impossible
    if not detect_ultraedge._ball_near_bat:
        return False
    try:
        audio, sr = librosa.load(video_path, sr=None)
    except:
        return False

    # Short-time energy (bat contact is very sharp)
    frame_len = int(0.01 * sr)   # 10 ms
    hop_len = int(0.005 * sr)    # 5 ms

    energy = librosa.feature.rms(
        y=audio,
        frame_length=frame_len,
        hop_length=hop_len
    )[0]

    mean_energy = energy.mean()
    peak_energy = energy.max()

    # Stronger threshold to avoid pitch/pad false spikes
    if peak_energy > mean_energy * 10:
        return True

    return False


def detect_stump_hit(trajectory):
    if not trajectory:
        return False

    # Normalized stump zone (camera independent, conservative)
    for p in trajectory:
        x = p.get("x", 0)
        y = p.get("y", 0)

        if 0.46 <= x <= 0.54 and y <= 0.08:
            return True

    return False


def analyze_training(data):
    trajectory = data.get("trajectory", [])
    video_path = data.get("video_path")

    near_bat = ball_near_bat(trajectory)
    detect_ultraedge._ball_near_bat = near_bat

    ultraedge = detect_ultraedge(video_path) if (video_path and near_bat) else False
    hits_stumps = detect_stump_hit(trajectory)

    if ultraedge:
        decision = "NOT OUT"
        reason = "Bat involved (UltraEdge detected)"
    elif hits_stumps:
        decision = "OUT"
        reason = "Ball hit the stumps"
    else:
        decision = "NOT OUT"
        reason = "Ball missed stumps"

    return {
        "speed_kmph": data.get("speed_kmph"),
        "swing": data.get("swing"),
        "spin": data.get("spin"),
        "trajectory": trajectory,
        "drs": {
            "ultraedge": ultraedge,
            "hits_stumps": hits_stumps,
            "decision": decision,
            "reason": reason
        }
    }