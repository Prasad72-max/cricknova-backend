# defensive_index.py
import math

class DefensiveIndex:

    def score(self, bat_angle, impact_alignment, head_stability, deviation):
        """
        bat_angle: ideal ~ 0–10 degrees
        impact_alignment: 0–1
        head_stability: 0–1
        deviation: ball movement (less is better)
        """

        angle_score = max(0, 30 - abs(bat_angle)) / 30 * 30
        align_score = impact_alignment * 25
        head_score = head_stability * 25
        deviation_penalty = max(0, 20 - deviation) / 20 * 20

        total = angle_score + align_score + head_score + deviation_penalty
        return round(min(total, 100), 1)