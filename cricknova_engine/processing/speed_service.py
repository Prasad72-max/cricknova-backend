from .ball_tracker import BallTracker
from .speed import BallSpeedCalculator

def estimate_speed(video_path):
    """
    Physics-based ball speed estimation.
    Allows low-confidence estimation for short clips.
    No hardcoded fallback values.
    """

    tracker = BallTracker()
    speed_calc = BallSpeedCalculator(fps=30)

    positions = tracker.track_ball(video_path)

    # If tracking completely failed
    if positions is None or len(positions) < 3:
        return None

    # Calculate speed even for low-confidence (short clips)
    speed = speed_calc.calculate_speed(positions)

    # Validate physical bounds
    if speed is None:
        return None

    if speed <= 0:
        return None

    # Upper bound safety (international fast bowling max ~170 km/h)
    if speed > 190:
        return None

    return round(speed, 1)