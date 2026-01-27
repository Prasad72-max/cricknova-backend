# swing_heatmap.py

class SwingHeatmap:

    def __init__(self):
        self.swing_points = []     # [(x, y, speed, confidence)]
        self.impact_points = []    # [(x, y)]
        self.power_map = []        # speed-based power values
        self.confidence_map = []   # confidence values

    def add_swing_point(self, x, y, speed, confidence):
        self.swing_points.append((x, y, speed, confidence))
        self.power_map.append(speed)
        self.confidence_map.append(confidence)

    def add_impact(self, x, y):
        self.impact_points.append((x, y))

    def get_heatmap_data(self):
        """
        Returns observed swing and impact data derived from video physics.
        Includes confidence-aware metrics for UI rendering.
        """
        avg_confidence = (
            sum(self.confidence_map) / len(self.confidence_map)
            if self.confidence_map else None
        )

        return {
            "swing_points": self.swing_points,
            "impact_points": self.impact_points,
            "avg_power": (sum(self.power_map) / len(self.power_map)) if self.power_map else None,
            "avg_confidence": avg_confidence
        }