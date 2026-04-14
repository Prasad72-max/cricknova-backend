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

def detect_ultraedge(video_path, trajectory):
    # UltraEdge disabled for stability and to avoid scripted NOT OUT
    return False

def detect_stump_hit(trajectory):
    """FIXED: Physics-based stump zone + post-pitch only"""
    if not trajectory or len(trajectory) < 8:
        return 0.0
    
    # Ball MUST pitch first (post-bounce frames only)
    y_positions = [p.get("y", 0) for p in trajectory]
    pitch_frame = np.argmax(y_positions)  # Highest Y = bounce (correct for screen coordinates)
    post_pitch = trajectory[max(0, pitch_frame):]  # ONLY post-pitch
    
    if len(post_pitch) < 3:
        return 0.0
    
    hits = 0
    for p in post_pitch:
        x, y = p.get("x", 0), p.get("y", 0)
        # NORMAL MODE stump zone (wider)
        if 0.38 <= x <= 0.62 and 0.55 <= y <= 1.00:
            hits += 1

    # If no direct hits detected, project future path (basic linear physics)
    if hits == 0 and len(post_pitch) >= 3:
        last_points = post_pitch[-3:]
        dx = last_points[-1]["x"] - last_points[-2]["x"]
        dy = last_points[-1]["y"] - last_points[-2]["y"]

        proj_x = last_points[-1]["x"]
        proj_y = last_points[-1]["y"]

        for _ in range(8):  # lighter projection, reduce false hits
            proj_x += dx
            proj_y += dy
            if 0.38 <= proj_x <= 0.62 and 0.55 <= proj_y <= 1.00:
                return 0.80  # stronger projected hit confidence

    # Smooth confidence scaling (avoid extreme sensitivity)
    confidence = hits / max(len(post_pitch), 1)
    return min(confidence, 1.0)

def analyze_training(data):
    trajectory = data.get("trajectory", [])
    video_path = data.get("video_path")
    
    global ball_near_bat_cache
    ball_near_bat_cache = ball_near_bat(trajectory)  # FIXED cache
    
    ultraedge = False  # Fully disabled for stable DRS
    stump_confidence = detect_stump_hit(trajectory)
    
    # Simplified physics-only decision tree
    if stump_confidence >= 0.55:
        decision = "OUT"
        reason = "Ball hitting stumps"
    elif stump_confidence >= 0.30:
        decision = "UMPIRE'S CALL"
        reason = "Clipping stumps - marginal"
    else:
        decision = "NOT OUT"
        reason = "Ball missing stumps"
    
    return {
        "drs": {
            "ultraedge": ultraedge,
            "stump_confidence": round(stump_confidence, 2),
            "decision": decision,
            "reason": reason,
            "pitch_frame": np.argmax([p.get("y", 0) for p in trajectory]) if trajectory else 0
        }
    }
