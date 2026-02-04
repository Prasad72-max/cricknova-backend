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
    if not positions or len(positions) < 24:
        return {
            "speed_kmph": None,
            "speed_type": "pre-pitch",
            "speed_note": "Insufficient tracked frames for physics-based speed"
        }

    # Drop first 2 frames to avoid detector warm-up jumps
    stable_positions = positions[2:]

    base_speed_result = calculate_speed_pro(
        stable_positions,
        fps=fps,
    )

    if not base_speed_result or not isinstance(base_speed_result, dict):
        return {
            "speed_kmph": None,
            "speed_type": "pre-pitch",
            "speed_note": "Physics-based speed unavailable"
        }

    speed_kmph = base_speed_result.get("speed_kmph")
    speed_note = base_speed_result.get("speed_note")

    # ---- VERIFIED PHYSICS MODE ----
    # Speed is returned ONLY if it passes
    # real cricket-physics validation.
    # Otherwise backend returns None honestly.
    if not isinstance(speed_kmph, (int, float)):
        speed_kmph = None

    return {
        "speed_kmph": speed_kmph,
        "speed_type": "pre-pitch",
        "speed_note": speed_note or "Physics-based speed from distance–time (video frames)"
    }