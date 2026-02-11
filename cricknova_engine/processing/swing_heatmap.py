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
        self._forced = False
        # (x, y) impact / pitch points
        self.impact_points = []
        # speed samples for averaging
        self.speed_samples = []
        self.MAX_POINTS = 120

    def add_swing_point(self, x, y, speed=None):
        """
        Add a swing observation point.
        Speed is optional and used only if reliable.
        Lateral position is normalized relative to the first point
        to avoid camera left/right bias.
        """

        # Record swing ONLY before pitch/impact (real swing happens in air)
        if self.impact_points:
            return

        # Preserve raw lateral displacement (do not re-normalize here)
        norm_x = float(x)


        # preserve signed lateral displacement for swing direction
        self.swing_points.append((norm_x, float(y), speed))

        if speed is not None:
            self.speed_samples.append(speed)

        # Keep only the most recent stable points (Render-safe)
        if len(self.swing_points) > self.MAX_POINTS:
            self.swing_points = self.swing_points[-self.MAX_POINTS:]
        if len(self.speed_samples) > self.MAX_POINTS:
            self.speed_samples = self.speed_samples[-self.MAX_POINTS:]

    def add_impact(self, x, y):
        """
        Register pitch or impact location.
        """
        if self.impact_points:
            return

        self.impact_points.append((x, y))

        # Prevent unbounded growth
        if len(self.impact_points) > self.MAX_POINTS:
            self.impact_points = self.impact_points[-self.MAX_POINTS:]

    def get_heatmap_data(self):
        """
        Returns clean heatmap data for UI rendering.
        No confidence scores, no exaggeration.
        """
        # Always provide an average speed for UI stability
        if len(self.speed_samples) >= 2:
            avg_speed = sum(self.speed_samples) / float(len(self.speed_samples))
        elif len(self.speed_samples) == 1:
            avg_speed = self.speed_samples[0]
        else:
            avg_speed = 0.0


        return {
            "swing_points": self.swing_points,
            "impact_points": self.impact_points,
            "avg_speed": avg_speed
        }