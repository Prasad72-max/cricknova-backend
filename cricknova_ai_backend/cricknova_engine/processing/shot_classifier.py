# ------------------------------------------------------------
# SHOT CLASSIFIER ENGINE (IMPROVED & FIXED)
# ------------------------------------------------------------

import numpy as np

class ShotClassifier:

    def classify(self, trajectory, positions, contact_frame):
        if trajectory is None or contact_frame is None:
            return "0"

        dx = trajectory["dx"]
        dy = trajectory["dy"]
        angle = trajectory["angle_deg"]

        speed_before = self._speed(positions, contact_frame - 1, contact_frame - 2)
        speed_after  = self._speed(positions, contact_frame + 1, contact_frame)

        distance = self._travel_distance(positions, contact_frame)

        # ---------------------------------------------------
        # 1) FIRST PRIORITY = WICKET CHECK
        # ---------------------------------------------------
        if speed_after < speed_before * 0.20 and distance < 40:
            return "W"

        # ---------------------------------------------------
        # 2) DISTANCE OVERRIDES ANGLE
        # ---------------------------------------------------
        if distance > 340: 
            return "6"
        if distance > 220:
            return "4"
        if distance > 120:
            return "2"
        if distance > 60:
            return "1"

        # ---------------------------------------------------
        # 3) ANGLE-BASED CLASSIFICATION
        # ---------------------------------------------------

        # STRAIGHT REGION
        if -10 <= angle <= 10:
            if speed_after > speed_before * 2.8:
                return "6"
            if speed_after > speed_before * 1.7:
                return "4"
            return "0"

        # OFF-SIDE
        if -10 <= angle <= 60:
            if speed_after > speed_before * 2.4:
                return "6"
            if speed_after > speed_before * 1.8:
                return "4"
            return "1"

        # LEG-SIDE
        if 60 < angle <= 130:
            if speed_after > speed_before * 2.2:
                return "6"
            if speed_after > speed_before * 1.5:
                return "4"
            return "1"

        return "0"


    def _speed(self, positions, f1, f2):
        if f1 < 0 or f2 < 0:
            return 0.0001
        if positions[f1] is None or positions[f2] is None:
            return 0.0001

        p1 = np.array(positions[f1])
        p2 = np.array(positions[f2])
        return float(np.linalg.norm(p1 - p2))

    def _travel_distance(self, positions, contact_frame):
        start = positions[contact_frame]
        if start is None:
            return 0.0

        total = 0
        prev = np.array(start)

        for p in positions[contact_frame+1:]:
            if p is None:
                break
            p = np.array(p)
            total += float(np.linalg.norm(p - prev))
            prev = p

        return total