# swing_heatmap.py

class SwingHeatmap:
    """
    Heatmap generator for swing visualization.
    Stores ONLY observed trajectory-derived data.
    No artificial confidence or inflated metrics.
    """

    def __init__(self):
        # (x, y, speed) points along ball path
        self.swing_points = []
        # (x, y) impact / pitch points
        self.impact_points = []
        # speed samples for averaging
        self.speed_samples = []

    def add_swing_point(self, x, y, speed=None):
        """
        Add a swing observation point.
        Speed is optional and used only if reliable.
        """
        self.swing_points.append((x, y, speed))
        if speed is not None:
            self.speed_samples.append(speed)

    def add_impact(self, x, y):
        """
        Register pitch or impact location.
        """
        self.impact_points.append((x, y))

    def get_heatmap_data(self):
        """
        Returns clean heatmap data for UI rendering.
        No confidence scores, no exaggeration.
        """
        avg_speed = (
            sum(self.speed_samples) / len(self.speed_samples)
            if self.speed_samples else None
        )

        return {
            "swing_points": self.swing_points,
            "impact_points": self.impact_points,
            "avg_speed": avg_speed
        }