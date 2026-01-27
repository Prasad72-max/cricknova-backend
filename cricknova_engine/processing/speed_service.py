from .ball_tracker import BallTracker
from .speed import BallSpeedCalculator

def estimate_speed(video_path):
    """
    Physics-based ball speed estimation from video frames.
    - No scripted limits or fake realism
    - Returns speed with confidence when available
    - Honest fallback when tracking is insufficient
    """

    tracker = BallTracker()
    # FPS will be inferred internally from video metadata
    speed_calc = BallSpeedCalculator()

    positions = tracker.track_ball(video_path)

    if not positions or len(positions) < 6:
        return {
            "speed_kmph": None,
            "speed_type": "pre-pitch",
            "confidence": 0.0,
            "speed_note": "Insufficient frames for physics-based speed"
        }

    base_speed = speed_calc.calculate_speed(positions)

    if base_speed is None:
        return {
            "speed_kmph": None,
            "speed_type": "pre-pitch",
            "confidence": 0.0,
            "speed_note": "Tracking incomplete, speed not reliable"
        }

    if isinstance(base_speed, dict):
        return base_speed

    return {
        "speed_kmph": round(float(base_speed), 1),
        "speed_type": "pre-pitch",
        "confidence": 1.0,
        "speed_note": "Physics-based speed (confidence assumed high)"
    }