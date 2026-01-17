# FILE: cricknova_engine/processing/foot_landing.py

class FootLandingDetector:

    def __init__(self, crease_y_norm=0.15):
        """
        crease_y_norm: normalized popping crease position (0 to 1).
        """
        self.crease_y_norm = crease_y_norm

    def detect_foot_landing(self, foot_positions):
        """
        Detects landing point of bowler's front foot.
        """
        if len(foot_positions) == 0:
            return {"x_norm": 0.5, "y_norm": 0.2, "is_no_ball": False}

        # Landing = highest Y value (foot closest to ground)
        landing = max(foot_positions, key=lambda p: p[1])
        fx, fy = landing

        x_norm = fx / 1080
        y_norm = fy / 1920

        is_no_ball = y_norm < self.crease_y_norm

        return {
            "x_norm": round(x_norm, 3),
            "y_norm": round(y_norm, 3),
            "is_no_ball": is_no_ball
        }

    def build_foot_map(self, foot_points):
        """
        Returns points for scatter visualization.
        """
        return foot_points