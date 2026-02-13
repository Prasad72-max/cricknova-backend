import numpy as np
import librosa

# FIXED: Static class variable bug
ball_near_bat_cache = False  # Global instead of ._ball_near_bat

def ball_near_bat(trajectory):
    """Bat zone detection - FIXED tighter window"""
    if not trajectory or len(trajectory) < 3:
        return False
    
    for p in trajectory:
        x, y = p.get("x", 0), p.get("y", 0)
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
    """FIXED: Physics-based stump zone + post-pitch only"""
    if not trajectory or len(trajectory) < 8:
        return 0.0
    
    # Ball MUST pitch first (post-bounce frames only)
    y_positions = [p.get("y", 0) for p in trajectory]
    pitch_frame = np.argmin(y_positions)  # Lowest point = bounce (FIXED)
    post_pitch = trajectory[max(0, pitch_frame):]  # ONLY post-pitch
    
    if len(post_pitch) < 3:
        return 0.0
    
    hits = 0
    for p in post_pitch:
        x, y = p.get("x", 0), p.get("y", 0)
        # IMPROVED stump zone (realistic full stump height)
        if 0.44 <= x <= 0.56 and 0.60 <= y <= 0.95:
            hits += 1

    # If no direct hits detected, project future path (basic linear physics)
    if hits == 0 and len(post_pitch) >= 3:
        last_points = post_pitch[-3:]
        dx = last_points[-1]["x"] - last_points[-2]["x"]
        dy = last_points[-1]["y"] - last_points[-2]["y"]

        proj_x = last_points[-1]["x"]
        proj_y = last_points[-1]["y"]

        for _ in range(12):  # project next 12 frames
            proj_x += dx
            proj_y += dy
            if 0.44 <= proj_x <= 0.56 and 0.60 <= proj_y <= 0.95:
                return 0.75  # strong projected hit confidence

    return hits / len(post_pitch)

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
    elif stump_confidence >= 0.70:  # Raised threshold
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
            "pitch_frame": np.argmax([p.get("y", 0) for p in trajectory]) if trajectory else 0
        }
    }
