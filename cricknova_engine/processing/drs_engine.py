"""
Clean DRS Engine for CrickNova
--------------------------------
Uses trajectory points to decide OUT / NOT OUT
No hardcoded fallback decisions.
"""

import math


class DRSEngine:

    def __init__(self):
        # Normalized stump zone (0–1 screen space)
        # Adjust if needed based on camera calibration
        self.stump_left = 0.45
        self.stump_right = 0.55

    def _project_to_stumps(self, trajectory):
        """
        Simple linear projection using last 3 trajectory points
        """
        if len(trajectory) < 3:
            return None

        p1 = trajectory[-3]
        p2 = trajectory[-2]
        p3 = trajectory[-1]

        dx = p3["x"] - p1["x"]
        dy = p3["y"] - p1["y"]

        if abs(dy) < 1e-5:
            return None

        # Project to y = 1.0 (batsman end)
        slope = dx / dy
        remaining_y = 1.0 - p3["y"]
        projected_x = p3["x"] + slope * remaining_y

        return projected_x

    def evaluate(self, trajectory):
        """
        trajectory: list of dicts [{"x": float, "y": float}]

        Returns:
        {
            "decision": "OUT" | "NOT_OUT",
            "impact_zone": str,
            "stump_projection": float | None
        }
        """

        if not trajectory or len(trajectory) < 6:
            return {
                "decision": "NOT_OUT",
                "impact_zone": "INSUFFICIENT_DATA",
                "stump_projection": None
            }

        projected_x = self._project_to_stumps(trajectory)

        if projected_x is None:
            return {
                "decision": "NOT_OUT",
                "impact_zone": "NO_PROJECTION",
                "stump_projection": None
            }

        # Check stump zone
        if self.stump_left <= projected_x <= self.stump_right:
            decision = "OUT"
            zone = "HITTING"
        else:
            decision = "NOT_OUT"
            zone = "MISSING"

        return {
            "decision": decision,
            "impact_zone": zone,
            "stump_projection": round(projected_x, 3)
        }


def calculate_drs(trajectory):
    engine = DRSEngine()
    return engine.evaluate(trajectory)