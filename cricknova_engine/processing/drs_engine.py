import numpy as np
import librosa

def _get_xy(p):
    if isinstance(p, dict):
        return p.get("x", 0.0), p.get("y", 0.0)
    if isinstance(p, (list, tuple)) and len(p) >= 2:
        return float(p[0]), float(p[1])
    return 0.0, 0.0

# Global cache for bat detection
ball_near_bat_cache = False

def ball_near_bat(trajectory):
    """Bat zone detection - realistic swing path"""
    if not trajectory or len(trajectory) < 3:
        return False
    
    for p in trajectory:
        x, y = _get_xy(p)
        # Tighter bat zone (normalized screen coords)
        if 0.45 <= x <= 0.55 and 0.25 <= y <= 0.38:
            return True
    return False

def detect_ultraedge(video_path, trajectory):
    """UltraEdge snick detection with adaptive threshold"""
    global ball_near_bat_cache
    if not ball_near_bat_cache:
        return False
    
    try:
        audio, sr = librosa.load(video_path, sr=None, duration=5.0)
    except:
        return False

    frame_len = int(0.008 * sr)  # 8ms windows
    hop_len = int(0.004 * sr)    # 4ms hop
    
    energy = librosa.feature.rms(y=audio, frame_length=frame_len, hop_length=hop_len)[0]
    
    # Adaptive threshold for varying pitch noise
    mean_energy = np.mean(energy)
    std_energy = np.std(energy)
    if len(energy) > 10 and np.max(energy) > mean_energy + 8 * std_energy:
        return True
    return False

def detect_stump_hit(trajectory):
    """DRS 2.0 – Projection Based Ball Tracking"""

    if not trajectory or len(trajectory) < 6:
        print("DRS 2.0 → insufficient trajectory")
        return 0.0

    # ---- 1️⃣ Find Bounce (highest Y = closest to ground) ----
    y_positions = [_get_xy(p)[1] for p in trajectory]
    pitch_frame = int(np.argmax(y_positions))

    # Reject very short balls (bouncer logic)
    if pitch_frame < len(trajectory) * 0.25:
        print("DRS 2.0 → short ball")
        return 0.0

    post_pitch = trajectory[pitch_frame:]

    if len(post_pitch) < 3:
        print("DRS 2.0 → not enough post-bounce data")
        return 0.0

    # ---- 2️⃣ Fit Linear Model (x = m*y + c) ----
    xs = np.array([_get_xy(p)[0] for p in post_pitch])
    ys = np.array([_get_xy(p)[1] for p in post_pitch])

    try:
        m, c = np.polyfit(ys, xs, 1)
    except:
        print("DRS 2.0 → polyfit failed")
        return 0.0

    # ---- 3️⃣ Project To Stump Plane ----
    stump_y_plane = 0.90
    projected_x = m * stump_y_plane + c

    # ---- 4️⃣ Stump Geometry (Normalized 0–1 scale) ----
    stump_center_x = 0.62
    stump_half_width = 0.07

    stump_x_min = stump_center_x - stump_half_width
    stump_x_max = stump_center_x + stump_half_width

    print("DRS 2.0 → projected_x:", round(projected_x, 3))

    # ---- 5️⃣ Decision Confidence ----
    if stump_x_min <= projected_x <= stump_x_max:
        stability = 1 - min(np.std(xs), 0.1)
        confidence = max(min(stability, 1.0), 0.4)
        print("DRS 2.0 → HITTING")
        return confidence

    print("DRS 2.0 → MISSING")
    return 0.0

def analyze_training(data):
    """Main DRS analysis - TV DRS physics logic"""
    trajectory = data.get("trajectory", [])
    video_path = data.get("video_path")
    
    global ball_near_bat_cache
    ball_near_bat_cache = ball_near_bat(trajectory)
    
    # UltraEdge first (highest priority)
    ultraedge = bool(video_path and ball_near_bat_cache and detect_ultraedge(video_path, trajectory))
    stump_confidence = detect_stump_hit(trajectory)
    
    # FIXED: Realistic decision thresholds
    if ultraedge:
        decision = "NOT OUT"
        reason = "UltraEdge: Bat first contact"
    elif stump_confidence >= 0.45:  # Strong hit
        decision = "OUT"
        reason = "Ball projected to hit stumps"
    elif stump_confidence >= 0.25:  # Marginal
        decision = "UMPIRE'S CALL"
        reason = "Clipping stumps - marginal impact"
    else:
        decision = "NOT OUT"
        reason = "Missing stumps outside line"
    
    return {
        "speed": data.get("speed", 0),
        "swing": data.get("swing", "None"),
        "spin": data.get("spin", "None"),
        "trajectory": trajectory,
        "drs": {
            "ultraedge": ultraedge,
            "stump_confidence": round(stump_confidence, 2),
            "decision": decision,
            "reason": reason,
            "pitch_frame": int(np.argmin([_get_xy(p)[1] for p in trajectory])) if trajectory else 0
        }
    }
