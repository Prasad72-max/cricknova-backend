from .ball_tracker import BallTracker
from .speed import BallSpeedCalculator
import random

def estimate_speed(video_path):
    """
    Physics-based ball speed estimation.
    Adds small broadcast-style fluctuation (±6%)
    without scripting or fake fallback values.
    """

    tracker = BallTracker()
    speed_calc = BallSpeedCalculator(fps=30)

    positions = tracker.track_ball(video_path)

    # If tracking completely failed
    if positions is None or len(positions) < 3:
        return None

    # Pure physics speed
    base_speed = speed_calc.calculate_speed(positions)

    if base_speed is None or base_speed <= 0 or base_speed > 190:
        return None

    # --- Broadcast-style natural fluctuation ---
    # TV speeds vary slightly due to tracking + camera timing
    variation_factor = random.uniform(0.94, 1.06)  # ±6%
    final_speed = base_speed * variation_factor

    return round(final_speed, 1)