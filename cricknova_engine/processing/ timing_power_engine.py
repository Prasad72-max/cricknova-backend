import numpy as np


class TimingPowerEngine:

    def __init__(self):
        pass

    # --------------------------------------------------------
    # MAIN EVALUATION
    # --------------------------------------------------------
    def evaluate(self, speed_before, speed_after, distance, angle):
        timing = self._timing_score(speed_before, speed_after)
        power = self._power_score(speed_after, distance)
        rating = self._rating(timing, power)

        return {
            "timing_score": timing,
            "power_score": power,
            "overall_rating": rating
        }

    # --------------------------------------------------------
    # TIMING SCORE
    # --------------------------------------------------------
    def _timing_score(self, speed_before, speed_after):
        if speed_before <= 0:
            return 40

        ratio = speed_after / speed_before

        # sweet spot = ratio between 1.4 and 2.0
        if ratio < 1.0:
            return 20 + ratio * 20
        if ratio < 2.0:
            return 50 + (ratio - 1.0) * 40

        return min(100, 90 + (ratio - 2.0) * 5)

    # --------------------------------------------------------
    # POWER SCORE
    # --------------------------------------------------------
    def _power_score(self, speed_after, distance):
        score = (speed_after * 0.5) + (distance * 0.5)

        return max(0, min(100, score))

    # --------------------------------------------------------
    # OVERALL RATING (Stars)
    # --------------------------------------------------------
    def _rating(self, timing, power):
        avg = (timing + power) / 2

        if avg >= 90: return 5
        if avg >= 75: return 4
        if avg >= 55: return 3
        if avg >= 35: return 2
        return 1