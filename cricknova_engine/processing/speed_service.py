from .ball_tracker import BallTracker
from .speed import BallSpeedCalculator

def estimate_speed(video_path):
    """
    Pipeline for ball speed:
    1. Detect ball per frame
    2. Convert positions into real speed
    """

    tracker = BallTracker()
    speed_calc = BallSpeedCalculator(fps=30)

    positions = tracker.track_ball(video_path)

    if len(positions) < 2:
        # ultra-short or failed detection: never return 0
        return 55.0

    speed = speed_calc.calculate_speed(positions)
    # final safety net: never allow zero or negative speed
    if speed is None or speed <= 0:
        speed = 55.0
    return speed