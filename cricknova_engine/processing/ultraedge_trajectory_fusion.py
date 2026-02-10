# ------------------------------------------------------------
# ULTRAEDGE + TRAJECTORY FUSION ENGINE
# ------------------------------------------------------------

import numpy as np

class FusionEngine:
    def __init__(self):
        self.edge_threshold = 0.22      # lower: real bat edges often weak in video
        self.min_dev_for_edge = 3.0     # degrees, allow micro deflections
        self.min_speed_drop = 0.85      # realistic bat contact slowdown

    def fuse(self, trajectory, ultraedge_data, positions, contact_frame):
        """
        trajectory: { angle_before, angle_after, dx, dy, angle_deg }
        ultraedge_data: { spike: bool, spike_strength: float }
        positions: list of (x,y)
        contact_frame: index
        """

        if trajectory is None or contact_frame is None:
            return {"result": "NO CONTACT", "confidence": 0.0}

        spike        = ultraedge_data.get("spike", False)
        spike_power  = ultraedge_data.get("spike_strength", 0.0)

        angle        = trajectory["angle_deg"]
        angle_before = trajectory.get("angle_before", angle)
        angle_after  = trajectory.get("angle_after", angle)

        # angle deviation
        deviation = abs(angle_after - angle_before)

        # ball speed drop
        speed_before = self._speed(positions, contact_frame - 1, contact_frame - 2)
        speed_after  = self._speed(positions, contact_frame + 1, contact_frame)
        speed_ratio  = speed_after / (speed_before + 0.0001)

        # ------------------------------------------------------------
        # HARD EDGE CONFIRMATION (pure physics)
        # ------------------------------------------------------------
        if spike:
            if deviation >= self.min_dev_for_edge and speed_ratio <= self.min_speed_drop:
                return {
                    "result": "BAT",
                    "confidence": min(1.0, 0.6 + spike_power)
                }

        # ------------------------------------------------------------
        # VISION-ONLY EDGE (no audio spike, but real deflection)
        # ------------------------------------------------------------
        if deviation >= 8 and speed_ratio <= 0.78:
            return {
                "result": "BAT",
                "confidence": 0.55
            }

        # ------------------------------------------------------------
        # PAD / BODY CONTACT (no angular change, heavy energy loss)
        # ------------------------------------------------------------
        if deviation < 3 and speed_ratio <= 0.60:
            return {
                "result": "PAD",
                "confidence": 0.6
            }

        # ------------------------------------------------------------
        # No edge
        # ------------------------------------------------------------
        return {
            "result": "NO CONTACT",
            "confidence": 0.0
        }

    # ---------------------- UTILITY ----------------------
    def _speed(self, pos, f1, f2):
        if f1 < 0 or f2 < 0:
            return 0.0001
        if pos[f1] is None or pos[f2] is None:
            return 0.0001
        return float(np.linalg.norm(np.array(pos[f1]) - np.array(pos[f2])))