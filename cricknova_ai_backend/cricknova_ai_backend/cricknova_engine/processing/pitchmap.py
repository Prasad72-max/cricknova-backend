# FILE: cricknova_engine/processing/pitchmap.py

import numpy as np

class PitchMapEngine:

    def detect_bounce(self, positions):
        """
        Detects bounce point using vertical acceleration.

        Args:
            positions: list of (x, y)

        Returns:
            (bx, by) bounce point in pixel coordinates
        """

        if len(positions) < 5:
            return None

        ys = [p[1] for p in positions]

        # Vertical differences between frames
        diffs = [ys[i+1] - ys[i] for i in range(len(ys)-1)]

        # Bounce = sudden spike in downward motion
        bounce_idx = int(np.argmax(diffs))

        # Safety clamp
        bounce_idx = max(1, min(bounce_idx, len(positions)-2))

        return positions[bounce_idx]

    def normalize_bounce(self, bounce_point, img_width=720, img_height=1280):
        """
        Converts pixel bounce point to normalized 0–1 coordinates.
        """

        if bounce_point is None:
            return None

        x, y = bounce_point

        return {
            "nx": round(x / img_width, 4),
            "ny": round(y / img_height, 4)
        }

    def get_pitchmap(self, positions, img_width=720, img_height=1280):
        """
        Full pipeline:
            detect bounce → normalize → return dict
        """

        bounce = self.detect_bounce(positions)
        return self.normalize_bounce(bounce, img_width, img_height)