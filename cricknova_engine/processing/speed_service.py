from .ball_tracker import BallTracker
from .speed import calculate_speed_pro

# Real-world calibration (meters)
PITCH_LENGTH_METERS = 20.12

def estimate_speed(video_path):
    """
    Physics-based ball speed estimation from video frames.
    - No scripted limits or fake realism
    - Returns speed only (pure physics)
    - Honest null when tracking is insufficient
    """

    tracker = BallTracker()
    # FPS will be inferred internally from video metadata

    positions, fps = tracker.track_ball(video_path)

    # Require sufficient frames for physical stability
    if not positions or len(positions) < 8:
        return {
            "speed_kmph": None,
            "speed_type": "insufficient_data",
            "speed_note": "Not enough tracked frames for physics"
        }

    # Drop first 2 frames to avoid detector warm-up jumps
    stable_positions = positions[2:]

    # Limit frames to stable delivery window (Render-safe)
    if len(stable_positions) > 120:
        stable_positions = stable_positions[:120]

    base_speed_result = calculate_speed_pro(
        stable_positions,
        fps=fps,
    )

    # --- REAL-WORLD SPEED CONVERSION ---
    # Convert pixel speed to km/h using pitch length as scale
    if base_speed_result and isinstance(base_speed_result, dict):
        px_speed = base_speed_result.get("speed_px_per_sec")
        if isinstance(px_speed, (int, float)) and px_speed > 0:
            xs = [p[0] for p in stable_positions]
            ys = [p[1] for p in stable_positions]
            total_px = ((xs[-1] - xs[0]) ** 2 + (ys[-1] - ys[0]) ** 2) ** 0.5

            if total_px > 1:
                meters_per_pixel = PITCH_LENGTH_METERS / total_px
                speed_mps = px_speed * meters_per_pixel
                speed_kmph = speed_mps * 3.6
                base_speed_result["speed_kmph"] = round(speed_kmph, 1)

    if not base_speed_result or not isinstance(base_speed_result, dict):
        return {
            "speed_kmph": None,
            "speed_type": "invalid_physics",
            "speed_note": "Speed calculation failed"
        }

    speed_kmph = base_speed_result.get("speed_kmph")
    speed_note = base_speed_result.get("speed_note")

    # ---- VERIFIED PHYSICS MODE ----
    # Never fake speed. Pass through None honestly.
    if isinstance(speed_kmph, (int, float)):
        speed_kmph = float(speed_kmph)
    else:
        speed_kmph = None

    return {
        "speed_kmph": speed_kmph,
        "speed_type": "physics_calibrated",
        "speed_note": speed_note or "Pixel physics calibrated using pitch length (20.12 m)"
    }