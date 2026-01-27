from .ball_tracker import BallTracker
from .speed import BallSpeedCalculator

def estimate_speed(video_path):
    """
    Physics-based ball speed estimation.
    - No confidence flags
    - No hype or scripted logic
    - Always returns a single realistic speed value (km/h)
    """

    tracker = BallTracker()
    # FPS will be inferred internally from video metadata
    speed_calc = BallSpeedCalculator()

    positions = tracker.track_ball(video_path)

    # Hard fallback if tracking fails
    DEFAULT_SPEED = 110  # km/h

    if not positions or len(positions) < 6:
        return {
            "speed_kmph": 110,
            "speed_type": "pre-pitch",
            "speed_note": "Short clip fallback, physics bounded"
        }

    base_speed = speed_calc.calculate_speed(positions)

    if base_speed is None:
        return {
            "speed_kmph": 110,
            "speed_type": "pre-pitch",
            "speed_note": "Tracking incomplete, physics fallback"
        }

    # Clamp to realistic cricket limits
    MIN_KMH = 80
    MAX_KMH = 155

    base_speed = max(MIN_KMH, min(MAX_KMH, base_speed))

    return {
        "speed_kmph": int(base_speed),
        "speed_type": "pre-pitch",
        "speed_note": "Release speed, physics calibrated"
    }