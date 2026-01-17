# swing_heatmap.py

class SwingHeatmap:

    def __init__(self):
        self.swing_points = []     # [(x, y, speed)]
        self.impact_points = []    # [(x, y)]
        self.power_map = []        # speed/acc impact

    def add_swing_point(self, x, y, speed):
        self.swing_points.append((x, y, speed))
        self.power_map.append(speed)

    def add_impact(self, x, y):
        self.impact_points.append((x, y))

    def get_heatmap_data(self):
        """
        Returns synthetic values to draw on UI.
        """
        return {
            "swing_points": self.swing_points,
            "impact_points": self.impact_points,
            "avg_power": sum(self.power_map)/len(self.power_map) if self.power_map else 0
        }