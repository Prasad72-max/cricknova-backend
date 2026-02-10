"""
trajectory_engine.py
--------------------
Responsible for generating a physically meaningful ball trajectory
from tracked ball positions. This trajectory is the backbone for:
- swing detection
- spin detection
- speed refinement
- DRS (pitching, impact, wicket projection)

IMPORTANT:
This module must NEVER guess. If data is insufficient, it must say so.
"""

import numpy as np
from typing import List, Tuple, Dict


class TrajectoryEngine:
    def __init__(self):
        self.min_points = 6          # minimum frames required
        self.pitch_plane_y = 0.0     # y=0 treated as pitch plane
        self.stump_plane_x = 0.0     # x=0 treated as stump line

    # -----------------------------
    # Public API
    # -----------------------------
    def build_trajectory(self, points: List[Tuple[float, float, float]]) -> Dict:
        """
        points: list of (x, y, t)
        x -> lateral (left/right)
        y -> down-the-pitch
        t -> time (seconds)
        """

        if len(points) < self.min_points:
            return self._insufficient("TOO_FEW_POINTS")

        pts = np.array(points, dtype=np.float64)

        # sort by time
        pts = pts[np.argsort(pts[:, 2])]

        # smooth to remove jitter
        pts[:, 0] = self._smooth(pts[:, 0])
        pts[:, 1] = self._smooth(pts[:, 1])

        # split pre and post pitch
        pre, post = self._split_on_pitch(pts)

        if pre is None or post is None:
            return self._insufficient("NO_CLEAR_PITCH")

        # fit curves
        pre_fit = self._fit_quadratic(pre)
        post_fit = self._fit_quadratic(post)

        if pre_fit is None or post_fit is None:
            return self._insufficient("FIT_FAILED")

        # derive physics
        swing = self._detect_swing(pre_fit)
        spin = self._detect_spin(pre_fit, post_fit)

        # project to stumps for DRS
        stump_y = self._project_to_stumps(post_fit)

        return {
            "status": "ok",
            "trajectory": pts.tolist(),
            "pre_pitch_fit": pre_fit.tolist(),
            "post_pitch_fit": post_fit.tolist(),
            "swing": swing,
            "spin": spin,
            "stump_y_at_impact": stump_y,
        }

    # -----------------------------
    # Helpers
    # -----------------------------
    def _smooth(self, arr, k=3):
        if len(arr) < k:
            return arr
        out = arr.copy()
        for i in range(1, len(arr) - 1):
            out[i] = (arr[i - 1] + arr[i] + arr[i + 1]) / 3.0
        return out

    def _split_on_pitch(self, pts):
        idx = np.argmin(np.abs(pts[:, 1] - self.pitch_plane_y))
        if idx < 2 or idx > len(pts) - 3:
            return None, None
        return pts[:idx + 1], pts[idx:]

    def _fit_quadratic(self, pts):
        try:
            t = pts[:, 2] - pts[0, 2]
            x = pts[:, 0]
            y = pts[:, 1]

            cx = np.polyfit(t, x, 2)
            cy = np.polyfit(t, y, 2)
            return np.vstack([cx, cy])
        except Exception:
            return None

    def _detect_swing(self, fit):
        # lateral acceleration before pitch (real physics only)
        ax = 2 * fit[0][0]

        # very small values are noise → no decision
        if abs(ax) < 0.008:
            return None

        return "In Swing" if ax < 0 else "Out Swing"

    def _detect_spin(self, pre, post):
        pre_ax = 2 * pre[0][0]
        post_ax = 2 * post[0][0]
        delta = post_ax - pre_ax

        # below noise floor → no spin detected
        if abs(delta) < 0.01:
            return None

        # sign convention: +ve = leg spin, -ve = off spin
        return "Leg Spin" if delta > 0 else "Off Spin"

    def _project_to_stumps(self, fit):
        """
        Solve y(t) = stump_plane_x
        """
        a, b, c = fit[1]
        c -= self.stump_plane_x

        disc = b * b - 4 * a * c
        if disc < 0:
            return None

        t = (-b + np.sqrt(disc)) / (2 * a)
        return float(np.polyval(fit[0], t))

    def _insufficient(self, reason):
        return {
            "status": "insufficient_data",
            "reason": reason,
            "trajectory": []
        }