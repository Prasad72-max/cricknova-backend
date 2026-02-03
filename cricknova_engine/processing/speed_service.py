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

    if not positions:
        return {
            "speed_kmph": None,
            "speed_type": "pre-pitch",
            "speed_note": "Physics-based speed unavailable"
        }

    base_speed_result = calculate_speed_pro(
        positions,
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

    # ---- HARD PHYSICS SANITY CHECK ----
    # Reject impossible cricket speeds instead of showing fake numbers
    if not isinstance(speed_kmph, (int, float)):
        speed_kmph = None
    elif speed_kmph < 50 or speed_kmph > 180:
        speed_kmph = None

    return {
        "speed_kmph": speed_kmph,
        "speed_type": "pre-pitch",
        "speed_note": speed_note or "Physics-based speed from distance–time (video frames)"
    }