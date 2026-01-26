from .ball_tracker import BallTracker
from .speed import BallSpeedCalculator

def estimate_speed(video_path):
    """
    Physics-based ball speed estimation.
    Returns None if tracking confidence is insufficient.
    No hardcoded or fallback speeds.
    """

    tracker = BallTracker()
    speed_calc = BallSpeedCalculator(fps=30)

    positions = tracker.track_ball(video_path)

    # If tracking failed or too few points, do NOT guess speed
    if positions is None or len(positions) < 5:
        return None

    speed = speed_calc.calculate_speed(positions)

    # If calculation fails or is non-physical, return None
    if speed is None or speed <= 0 or speed > 180:
        return None

    return speed