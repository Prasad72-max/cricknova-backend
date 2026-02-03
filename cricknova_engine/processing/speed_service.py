from .ball_tracker import BallTracker
from .speed import BallSpeedCalculator

def estimate_speed(video_path):
    """
    Physics-based ball speed estimation from video frames.
    - No scripted limits or fake realism
    - Returns speed only (pure physics)
    - Honest null when tracking is insufficient
    """

    tracker = BallTracker()
    # FPS will be inferred internally from video metadata
    speed_calc = BallSpeedCalculator()

    positions, fps = tracker.track_ball(video_path)

    if not positions or len(positions) < 6:
        return {
            "speed_kmph": None,
            "speed_type": "pre-pitch",
            "speed_note": "Insufficient frames for physics-based speed"
        }

    base_speed = speed_calc.calculate_speed(positions, fps)

    if base_speed is None:
        return {
            "speed_kmph": None,
            "speed_type": "pre-pitch",
            "speed_note": "Tracking incomplete, speed not reliable"
        }

    if isinstance(base_speed, dict):
        return base_speed

    return {
        "speed_kmph": round(float(base_speed), 1),
        "speed_type": "pre-pitch",
        "speed_note": "Physics-based speed"
    }