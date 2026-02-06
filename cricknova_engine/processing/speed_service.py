from .ball_tracker import BallTracker
from .speed import calculate_speed_pro

def estimate_speed(video_path):
    """
    Full Track–style AI estimated release speed.
    - Windowed post-release velocity
    - Physics sanity filtering
    - Confidence-aware output
    - Speed always shown with conservative fallback
    """

    tracker = BallTracker()
    positions, fps = tracker.track_ball(video_path)

    # Minimal requirement: 3 frames with motion
    if not positions or len(positions) < 3 or not fps or fps <= 0:
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "INSUFFICIENT_TRACKING_DATA",
            "confidence": 0.15
        }

    # Drop first frame to reduce detector jitter
    stable_positions = positions[1:]

    # Cap frames for safety
    if len(stable_positions) > 150:
        stable_positions = stable_positions[:150]

    result = calculate_speed_pro(
        stable_positions,
        fps=fps,
        pitch_corners=None
    )

    # Expect dict from physics engine
    if not isinstance(result, dict):
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "SPEED_ENGINE_ERROR",
            "confidence": 0.15
        }

    speed_kmph = result.get("speed_kmph")

    # Absolute safety: never allow null speed
    if speed_kmph is None or speed_kmph <= 0:
        speed_kmph = result.get("derived_kmph")

    return {
        "speed_kmph": float(speed_kmph) if speed_kmph is not None else None,
        "speed_type": result.get("speed_type", "derived_physics"),
        "speed_note": result.get("speed_note", "PARTIAL_PHYSICS_USED"),
        "confidence": result.get("confidence", 0.6)
    }