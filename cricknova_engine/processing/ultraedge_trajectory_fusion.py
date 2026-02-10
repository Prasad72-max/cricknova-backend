# ------------------------------------------------------------
# ULTRAEDGE + TRAJECTORY FUSION ENGINE
# ------------------------------------------------------------

import numpy as np

class FusionEngine:
    def __init__(self):
        self.edge_threshold = 0.35      # more sensitive to real bat contact
        self.min_dev_for_edge = 6       # allow smaller deflection
        self.min_speed_drop = 0.65      # realistic post-bat slowdown

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
        # Vision-only detection (strong deviation + slowdown)
        # ------------------------------------------------------------
        if deviation > 12 and speed_ratio < 0.70:
            return {
                "result": "BAT",
                "confidence": 0.5
            }

        # ------------------------------------------------------------
        # PAD / LBW DEFLECTION (no spike, but clear slowdown + drop)
        # ------------------------------------------------------------
        if not spike:
            if speed_ratio < 0.55 and deviation < 4:
                return {
                    "result": "PAD",
                    "confidence": 0.55
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