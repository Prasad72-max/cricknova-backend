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
    """FIXED: Physics-based stump detection + adaptive confidence"""
    if not trajectory or len(trajectory) < 5:
        print("DRS DEBUG → Insufficient trajectory")
        return 0.0
    
    # Find pitch bounce (HIGHEST Y point in normalized coords)
    # In your coordinate system, larger Y = ball closer to ground
    y_positions = [_get_xy(p)[1] for p in trajectory]
    pitch_frame = int(np.argmax(y_positions))

    # Include bounce frame itself for projection safety
    post_pitch = trajectory[pitch_frame:]
    
    if not post_pitch or len(post_pitch) < 2:
        print("DRS DEBUG → No post-pitch frames")
        return 0.0
    
    hits = 0
    # UPDATED: Adjusted stump zone for your normalized trajectory scale
    # (Your trajectory Y values are around 1.6–1.9 range)
    stump_x_min, stump_x_max = 0.44, 0.56   # Slightly wider for variance
    stump_y_min, stump_y_max = 1.55, 1.90   # Match real trajectory height scale

    for p in post_pitch:
        x, y = _get_xy(p)
        if stump_x_min <= x <= stump_x_max and stump_y_min <= y <= stump_y_max:
            hits += 1

    # FIXED: Adaptive confidence based on ACTUAL post-pitch length
    confidence = min(hits / max(len(post_pitch), 3), 1.0)
    
    print("DRS DEBUG → total frames:", len(trajectory))
    print("DRS DEBUG → pitch_frame:", pitch_frame)
    print("DRS DEBUG → post_pitch frames:", len(post_pitch))
    print("DRS DEBUG → hits:", hits)
    print("DRS DEBUG → confidence:", round(confidence, 2))
    return confidence

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
