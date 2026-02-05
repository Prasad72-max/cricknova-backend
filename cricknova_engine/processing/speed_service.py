from .ball_tracker import BallTracker
from .speed import calculate_speed_pro

def estimate_speed(video_path):
    """
    Full Track–style AI estimated release speed.
    - Windowed post-release velocity
    - Physics sanity filtering
    - Confidence-aware output
    - Speed shown only when reliable
    """

    tracker = BallTracker()
    positions, fps = tracker.track_ball(video_path)

    # Minimal requirement: 3 frames with motion
    if not positions or len(positions) < 3 or not fps or fps <= 0:
        return {
            "speed_kmph": None,
            "speed_px_per_sec": None,
            "speed_type": "unavailable",
            "speed_note": "INSUFFICIENT_TRACKING_DATA"
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
            "speed_px_per_sec": None,
            "speed_type": "invalid_physics",
            "speed_note": "SPEED_ENGINE_ERROR"
        }

    speed_px_per_sec = result.get("speed_px_per_sec")
    speed_kmph = result.get("speed_kmph")

    return {
        "speed_kmph": speed_kmph,
        "speed_type": result.get("speed_type", "ai_estimated_release"),
        "speed_note": result.get("speed_note", "FULLTRACK_STYLE_WINDOWED"),
        "confidence": result.get("confidence")
    }