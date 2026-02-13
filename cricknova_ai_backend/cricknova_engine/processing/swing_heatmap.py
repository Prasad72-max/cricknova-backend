# swing_heatmap.py

class SwingHeatmap:

    def __init__(self):
        self.swing_points = []     # [(x, y, speed)]
        self.impact_points = []    # [(x, y)]
        self.power_map = []        # speed/acc impact

    def add_swing_point(self, x, y, speed):
        # Prevent duplicate scripted points
        if self.swing_points:
            last_x, last_y, last_speed = self.swing_points[-1]
            if abs(last_x - x) < 0.002 and abs(last_y - y) < 0.002:
                return  # ignore near-identical repeated frame

        # Clamp unrealistic speed values
        speed = max(min(speed, 160), 0)

        self.swing_points.append((x, y, speed))
        self.power_map.append(speed)

    def add_impact(self, x, y):
        self.impact_points.append((x, y))

    def get_heatmap_data(self):
        """
        Returns normalized heatmap data for UI rendering.
        """

        if not self.power_map:
            avg_power = 0
        else:
            avg_power = sum(self.power_map) / len(self.power_map)

        # Normalize power for UI scale (0–100)
        normalized_power = min(max(avg_power, 0), 160) / 160 * 100

        return {
            "swing_points": self.swing_points[-120:],   # limit to last 120 points
            "impact_points": self.impact_points[-10:],  # limit impact points
            "avg_power": round(normalized_power, 2)
        }