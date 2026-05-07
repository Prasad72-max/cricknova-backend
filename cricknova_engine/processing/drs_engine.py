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
    """DRS 2.0 – Projection Based Ball Tracking with Physics Labels"""

    if not trajectory or len(trajectory) < 6:
        return {
            "confidence": 0.0,
            "pitching": "In Line",
            "impact": "In Line",
            "wickets": "Missing"
        }

    # ---- 1️⃣ Find Bounce (highest Y = closest to ground) ----
    y_positions = [_get_xy(p)[1] for p in trajectory]
    pitch_frame = int(np.argmax(y_positions))

    # Reject very short balls (bouncer logic)
    if pitch_frame < len(trajectory) * 0.15:
        return {"confidence": 0.0, "pitching": "Short Ball", "impact": "In Line", "wickets": "Missing"}

    post_pitch = trajectory[pitch_frame:]
    if len(post_pitch) < 3:
        return {"confidence": 0.0, "pitching": "In Line", "impact": "In Line", "wickets": "Missing"}

    # ---- 2️⃣ Fit Linear Model (x = m*y + c) ----
    xs = np.array([_get_xy(p)[0] for p in post_pitch])
    ys = np.array([_get_xy(p)[1] for p in post_pitch])

    try:
        m, c = np.polyfit(ys, xs, 1)
    except:
        return {"confidence": 0.0, "pitching": "In Line", "impact": "In Line", "wickets": "Missing"}

    # ---- 3️⃣ Project To Stump Plane ----
    stump_y_plane = 0.88
    projected_x = m * stump_y_plane + c

    # ---- 4️⃣ Stump Geometry (Normalized 0–1 scale) ----
    # Accuracy Fix: Use center of frame (0.5) as stumps aren't usually at 0.62 offset
    stump_center_x = 0.50
    stump_half_width = 0.06

    stump_x_min = stump_center_x - stump_half_width
    stump_x_max = stump_center_x + stump_half_width

    # ---- 5️⃣ Physics Status Labels ----
    pitch_x = _get_xy(trajectory[pitch_frame])[0]
    impact_x = _get_xy(trajectory[-1])[0]

    pitching = "In Line"
    if pitch_x < stump_center_x - 0.07: pitching = "Outside Leg"
    elif pitch_x > stump_center_x + 0.07: pitching = "Outside Off"

    impact = "In Line"
    if abs(impact_x - stump_center_x) > 0.12: impact = "Outside"
    elif abs(impact_x - stump_center_x) > 0.08: impact = "Umpires Call"

    hitting = stump_x_min <= projected_x <= stump_x_max
    wickets = "Hitting" if hitting else "Missing"
    
    # Margin of error / Umpires Call for wickets
    if not hitting and (stump_x_min - 0.03 <= projected_x <= stump_x_max + 0.03):
        wickets = "Umpires Call"

    # ---- 6️⃣ Decision Confidence ----
    stability = 1 - min(np.std(xs), 0.1)
    base_conf = 0.85 if hitting else (0.55 if wickets == "Umpires Call" else 0.15)
    confidence = max(min(base_conf * stability, 1.0), 0.0)

    return {
        "confidence": confidence,
        "pitching": pitching,
        "impact": impact,
        "wickets": wickets,
        "projected_x": float(projected_x)
    }

def analyze_training(data):
    """Main DRS analysis - TV DRS physics logic"""
    trajectory = data.get("trajectory", [])
    video_path = data.get("video_path")
    
    global ball_near_bat_cache
    ball_near_bat_cache = ball_near_bat(trajectory)
    
    # UltraEdge first (highest priority)
    ultraedge = bool(video_path and ball_near_bat_cache and detect_ultraedge(video_path, trajectory))
    stump_results = detect_stump_hit(trajectory)
    
    stump_confidence = stump_results["confidence"]
    pitching_text = stump_results["pitching"]
    impact_text = stump_results["impact"]
    wickets_text = stump_results["wickets"]

    # FIXED: Realistic decision thresholds
    if ultraedge:
        decision = "NOT OUT"
        reason = "UltraEdge: Bat first contact"
        wickets_text = "Missing" # Edge overrides hitting
    elif pitching_text == "Outside Leg":
        decision = "NOT OUT"
        reason = "Pitching outside leg stump"
    elif stump_confidence >= 0.75:  # Strong hit
        decision = "OUT"
        reason = "Ball projected to hit stumps"
    elif stump_confidence >= 0.45:  # Marginal
        decision = "UMPIRE'S CALL"
        reason = "Clipping stumps - marginal impact"
    else:
        decision = "NOT OUT"
        reason = "Missing stumps"
    
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
            "pitching_text": pitching_text,
            "impact_text": impact_text,
            "wickets_text": wickets_text,
            "pitch_frame": int(np.argmin([_get_xy(p)[1] for p in trajectory])) if trajectory else 0
        }
    }
