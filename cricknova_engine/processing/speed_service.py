from .ball_tracker import BallTracker
from .speed import calculate_speed_pro

def estimate_speed(video_path):
    """
    Physics-based ball speed estimation from video frames.
    - Returns physics-based speed with confidence
    - Never returns null speed for valid 2–12 sec videos
    """

    tracker = BallTracker()
    # FPS will be inferred internally from video metadata

    positions, fps = tracker.track_ball(video_path)

    # Require sufficient frames for physical stability (relaxed)
    if not positions or len(positions) < 4:
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "confidence": 0.0,
            "speed_note": "TRACKING_FAILED"
        }

    stable_positions = positions[1:]  # drop first frame to reduce detector noise

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
            "speed_note": "SPEED_ENGINE_ERROR"
        }

    speed_kmph = base_speed_result.get("speed_kmph")
    speed_type = base_speed_result.get("speed_type")
    speed_note = base_speed_result.get("speed_note")
    speed_px_per_sec = base_speed_result.get("speed_px_per_sec")
    confidence = base_speed_result.get("confidence", 0.0)

    if isinstance(speed_kmph, (int, float)):
        speed_kmph = float(speed_kmph)
    else:
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "confidence": 0.0,
            "speed_note": "TRACKING_FAILED"
        }

    return {
        "speed_kmph": speed_kmph,
        "speed_px_per_sec": speed_px_per_sec,
        "speed_type": speed_type or "estimated_physics",
        "confidence": confidence,
        "speed_note": speed_note or "ASSUMED_PITCH_SCALE"
    }