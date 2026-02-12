import numpy as np
import librosa

def _get_xy(p):
    if isinstance(p, dict):
        return p.get("x", 0.0), p.get("y", 0.0)
    if isinstance(p, (list, tuple)) and len(p) >= 2:
        return float(p[0]), float(p[1])
    return 0.0, 0.0

# FIXED: Static class variable bug
ball_near_bat_cache = False  # Global instead of ._ball_near_bat

def ball_near_bat(trajectory):
    """Bat zone detection - FIXED tighter window"""
    if not trajectory or len(trajectory) < 3:
        return False
    
    for p in trajectory:
        x, y = _get_xy(p)
        # TIGHTER bat zone (realistic swing path)
        if 0.45 <= x <= 0.55 and 0.25 <= y <= 0.38:  # Was too wide
            return True
    return False

def detect_ultraedge(video_path, trajectory):  # FIXED: Pass trajectory
    global ball_near_bat_cache
    if not ball_near_bat_cache:  # Use global cache
        return False
    
    try:
        audio, sr = librosa.load(video_path, sr=None, duration=5.0)  # Limit duration
    except:
        return False

    # FIXED: Better spike detection
    frame_len = int(0.008 * sr)  # 8ms (sharper)
    hop_len = int(0.004 * sr)    # 4ms
    
    energy = librosa.feature.rms(y=audio, frame_length=frame_len, hop_length=hop_len)[0]
    
    # ADAPTIVE threshold (pitch noise varies)
    mean_energy = np.mean(energy)
    std_energy = np.std(energy)
    if len(energy) > 10 and np.max(energy) > mean_energy + 8 * std_energy:
        return True
    return False

def detect_stump_hit(trajectory):
    """
    Physics-based stump prediction using linear regression
    on post-bounce trajectory points.
    """
    if not trajectory or len(trajectory) < 8:
        return 0.0

    # Extract numeric points
    points = [(_get_xy(p)[0], _get_xy(p)[1]) for p in trajectory]

    # Detect bounce (lowest y before upward trend)
    y_positions = [p[1] for p in points]
    pitch_frame = int(np.argmax(y_positions))

    # Use only post-bounce points
    post_pitch = points[pitch_frame:]
    if len(post_pitch) < 4:
        return 0.0

    xs = np.array([p[0] for p in post_pitch])
    ys = np.array([p[1] for p in post_pitch])

    # Linear regression: x = m*y + c
    try:
        m, c = np.polyfit(ys, xs, 1)
    except:
        return 0.0

    # Predict x at stump line (near batsman)
    stump_y = 0.85
    predicted_x = m * stump_y + c

    # Realistic stump corridor
    left_stump = 0.46
    right_stump = 0.54

    if left_stump <= predicted_x <= right_stump:
        # Confidence based on distance from center
        center = (left_stump + right_stump) / 2
        max_offset = (right_stump - left_stump) / 2
        offset = abs(predicted_x - center)
        confidence = 1 - (offset / max_offset)
        return max(0.0, min(1.0, confidence))

    return 0.0

def analyze_training(data):
    trajectory = data.get("trajectory", [])
    video_path = data.get("video_path")
    
    global ball_near_bat_cache
    ball_near_bat_cache = ball_near_bat(trajectory)  # FIXED cache
    
    # FIXED UltraEdge logic
    ultraedge = bool(video_path and ball_near_bat_cache and detect_ultraedge(video_path, trajectory))
    stump_confidence = detect_stump_hit(trajectory)
    
    # PHYSICS-BASED DECISION TREE (TV DRS logic)
    if ultraedge:
        decision = "NOT OUT"
        reason = "UltraEdge: Bat first contact"
    elif stump_confidence >= 0.6:
        decision = "OUT"
        reason = "Projected to hit middle stumps"
    elif stump_confidence >= 0.3:
        decision = "UMPIRE'S CALL"
        reason = "Clipping outer stump"
    else:
        decision = "NOT OUT"
        reason = "Projected to miss stumps"
    
    return {
        "drs": {
            "ultraedge": ultraedge,
            "stump_confidence": round(stump_confidence, 2),
            "decision": decision,
            "reason": reason,
            "pitch_frame": int(np.argmax([_get_xy(p)[1] for p in trajectory])) if trajectory else 0
        }
    }

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
        if 0.45 <= x <= 0.55 and 0.25 <= y <= 0.40:
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

    stump_y = 0.85
    predicted_x = np.polyval(coeffs, stump_y)

    left_stump = 0.46
    right_stump = 0.54

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
    elif stump_confidence >= 0.60:
        decision = "OUT"
        reason = "Projected ball hitting stumps"
    elif 0.30 <= stump_confidence < 0.60:
        decision = "UMPIRE'S CALL"
        reason = "Clipping stumps marginally"
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