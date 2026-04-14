# ------------------------------------------------------------
# ULTRAEDGE + TRAJECTORY FUSION ENGINE
# ------------------------------------------------------------

import numpy as np

class FusionEngine:
    def __init__(self):
        self.edge_threshold = 0.48     # tuned sensitivity
        self.min_dev_for_edge = 8      # degrees change after contact
        self.min_speed_drop = 0.55     # 45%+ drop means possible edge

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

        # safe frame bounds handling
        max_index = len(positions) - 1

        before_1 = max(0, contact_frame - 1)
        before_2 = max(0, contact_frame - 2)
        after_1  = min(max_index, contact_frame + 1)

        speed_before = self._speed(positions, before_1, before_2)
        speed_after  = self._speed(positions, after_1, contact_frame)

        # prevent false zero division or unstable ratios
        if speed_before <= 0.0001:
            speed_ratio = 1.0
        else:
            speed_ratio = speed_after / speed_before

        # ------------------------------------------------------------
        # HARD EDGE CONFIRMATION RULE
        # ------------------------------------------------------------
        if spike and spike_power > self.edge_threshold:
            if deviation > self.min_dev_for_edge and speed_ratio < self.min_speed_drop:
                return {
                    "result": "BAT",
                    "confidence": min(1.0, spike_power * 1.2)
                }

        # ------------------------------------------------------------
        # LIGHT EDGE (UltraEdge small spike + small deviation)
        # ------------------------------------------------------------
        if spike and spike_power > 0.25:
            if deviation > 4 and speed_ratio < 0.80:
                return {
                    "result": "BAT",
                    "confidence": spike_power
                }

        # ------------------------------------------------------------
        # Vision-only detection (if angle deviation is huge)
        # ------------------------------------------------------------
        if deviation > 15 and speed_ratio < 0.65:
            return {
                "result": "BAT",
                "confidence": 0.45
            }

        # ------------------------------------------------------------
        # Fallback: Any meaningful spike should influence decision
        # ------------------------------------------------------------
        if spike:
            # Even weak spike should not be ignored completely
            adjusted_confidence = max(0.20, min(1.0, spike_power * 0.75))
            return {
                "result": "BAT",
                "confidence": adjusted_confidence
            }

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