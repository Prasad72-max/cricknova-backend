import numpy as np
import librosa


def _get_xy(p):
    if isinstance(p, dict):
        return float(p.get("x", 0.0)), float(p.get("y", 0.0))
    if isinstance(p, (list, tuple)) and len(p) >= 2:
        return float(p[0]), float(p[1])
    return 0.0, 0.0


ball_near_bat_cache = False


def ball_near_bat(trajectory):
    if not trajectory or len(trajectory) < 3:
        return False

    for p in trajectory:
        x, y = _get_xy(p)
        if 0.40 <= x <= 0.60 and 0.22 <= y <= 0.45:
            return True
    return False


def detect_ultraedge(video_path):
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

    if len(energy) < 10:
        return False

    mean_energy = np.mean(energy)
    std_energy = np.std(energy)

    if std_energy == 0:
        return False

    return np.max(energy) > mean_energy + 8 * std_energy


def detect_stump_hit(trajectory):
    if not trajectory or len(trajectory) < 8:
        return 0.0

    points = [_get_xy(p) for p in trajectory]
    y_vals = [p[1] for p in points]

    pitch_index = int(np.argmax(y_vals))
    post_pitch = points[pitch_index:]

    if len(post_pitch) < 5:
        return 0.0

    xs = np.array([p[0] for p in post_pitch])
    ys = np.array([p[1] for p in post_pitch])

    try:
        coeffs = np.polyfit(ys, xs, 1)
    except Exception:
        return 0.0

    stump_y = 0.82
    predicted_x = np.polyval(coeffs, stump_y)

    left_stump = 0.44
    right_stump = 0.56

    if left_stump <= predicted_x <= right_stump:
        center = 0.50
        max_dev = (right_stump - left_stump) / 2
        confidence = 1.0 - abs(predicted_x - center) / max_dev
        return float(np.clip(confidence, 0.0, 1.0))

    return 0.0


def analyze_training(data):
    trajectory = data.get("trajectory", [])
    video_path = data.get("video_path")

    global ball_near_bat_cache
    ball_near_bat_cache = ball_near_bat(trajectory)

    ultraedge = bool(video_path and detect_ultraedge(video_path))
    stump_confidence = detect_stump_hit(trajectory)

    if ultraedge:
        decision = "NOT OUT"
        reason = "UltraEdge detected: bat involved"
    elif stump_confidence >= 0.50:
        decision = "OUT"
        reason = "Ball projected to hit stumps"
    elif 0.25 <= stump_confidence < 0.50:
        decision = "UMPIRE'S CALL"
        reason = "Ball marginally clipping stumps"
    else:
        decision = "NOT OUT"
        reason = "Ball missing stumps"

    pitch_frame = 0
    if trajectory:
        pitch_frame = int(np.argmax([_get_xy(p)[1] for p in trajectory]))

    return {
        "drs": {
            "ultraedge": ultraedge,
            "stump_confidence": round(stump_confidence, 2),
            "decision": decision,
            "reason": reason,
            "pitch_frame": pitch_frame
        }
    }