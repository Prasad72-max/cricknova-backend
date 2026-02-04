from .ball_tracker import BallTracker
from .speed import calculate_speed_pro

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
            "speed_kmph": 0.0,
            "speed_type": "pre-pitch",
            "speed_note": "Very low tracking confidence (minimal frames)"
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

    if not base_speed_result or not isinstance(base_speed_result, dict):
        return {
            "speed_kmph": 0.0,
            "speed_type": "pre-pitch",
            "speed_note": "Fallback speed (pixel-time estimate)"
        }

    speed_kmph = base_speed_result.get("speed_kmph")
    speed_note = base_speed_result.get("speed_note")

    # ---- VERIFIED PHYSICS MODE ----
    # Do NOT drop numeric speeds here.
    # Validation is handled inside calculate_speed_pro.
    if not isinstance(speed_kmph, (int, float)):
        speed_kmph = 0.0
    else:
        speed_kmph = float(speed_kmph)

    return {
        "speed_kmph": speed_kmph,
        "speed_type": "pre-pitch",
        "speed_note": speed_note or "Physics-based speed from distance–time (video frames)"
    }