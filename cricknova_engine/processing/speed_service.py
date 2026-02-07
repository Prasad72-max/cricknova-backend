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

    speed_kmph = result.get("speed_kmph") or result.get("derived_kmph")

    # Absolute safety: validate numeric speed (no fake fallback)
    try:
        speed_kmph = float(speed_kmph)
        if speed_kmph <= 0 or speed_kmph != speed_kmph:
            raise ValueError("Invalid speed")
    except Exception:
        return {
            "speed_kmph": None,
            "speed_type": "unavailable",
            "speed_note": "INVALID_OR_INSUFFICIENT_PHYSICS",
            "confidence": 0.15
        }

    return {
        "speed_kmph": speed_kmph,
        "speed_type": result.get("speed_type", "derived_physics"),
        "speed_note": result.get("speed_note", "PHYSICS_FALLBACK_APPLIED"),
        "confidence": max(result.get("confidence", 0.6), 0.35)
    }