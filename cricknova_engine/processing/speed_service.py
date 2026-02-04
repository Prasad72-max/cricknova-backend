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
        pitch_corners=None
    )

    if not isinstance(base_speed_result, dict):
        return {
            "speed_kmph": None,
            "speed_type": "invalid_physics",
            "speed_note": "Speed calculation failed"
        }

    speed_kmph = base_speed_result.get("speed_kmph")
    speed_type = base_speed_result.get("speed_type")
    speed_note = base_speed_result.get("speed_note")

    if isinstance(speed_kmph, (int, float)):
        speed_kmph = float(speed_kmph)
    else:
        speed_kmph = None

    return {
        "speed_kmph": speed_kmph,
        "speed_type": speed_type or "physics_uncalibrated",
        "speed_note": speed_note
    }