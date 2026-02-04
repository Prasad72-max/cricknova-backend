import math
import numpy as np

def unmirror_positions(positions):
    """
    Correct horizontal mirroring common in mobile cameras.
    Only applies correction if horizontal motion dominates.
    """
    if len(positions) < 2:
        return positions

    dx = abs(positions[-1][0] - positions[0][0])
    dy = abs(positions[-1][1] - positions[0][1])

    # If motion is mostly vertical, do NOT unmirror
    if dx < dy * 0.3:
        return positions

    xs = [p[0] for p in positions]
    min_x, max_x = min(xs), max(xs)
    return [((max_x - (x - min_x)), y) for x, y in positions]

def smooth_positions(positions, window=3):
    """
    Simple moving average smoothing to reduce tracker noise.
    """
    if len(positions) < window:
        return positions

    smoothed = []
    for i in range(len(positions)):
        xs, ys = [], []
        for j in range(max(0, i - window), min(len(positions), i + window + 1)):
            xs.append(positions[j][0])
            ys.append(positions[j][1])
        smoothed.append((sum(xs) / len(xs), sum(ys) / len(ys)))
    return smoothed

class SwingDetector:
    def __init__(self, fps=30):
        self.fps = fps

    def _line_angle(self, p1, p2):
        dx = p2[0] - p1[0]
        dy = p2[1] - p1[1]
        if abs(dx) < 1e-6:
            return 90.0
        return math.degrees(math.atan2(dy, dx))

    def _detect_pitch_index(self, positions):
        """
        Detect bounce using strongest vertical direction change.
        Falls back safely when bounce is weak.
        """
        ys = [p[1] for p in positions]
        diffs = np.diff(ys)
        if len(diffs) < 3:
            return None

        accel = np.abs(np.diff(diffs))
        if len(accel) == 0 or np.max(accel) < 0.8:
            return None

        idx = int(np.argmax(accel)) + 1
        return max(2, min(idx, len(positions) - 3))

    def detect_swing(self, positions):
        """
        Returns raw swing angle (degrees) based purely on trajectory.
        """
        # Limit frames to stable delivery window
        if len(positions) > 120:
            positions = positions[:120]

        # Render-safe minimum frames (keeps physics honest)
        if not positions or len(positions) < 8:
            return None

        positions = unmirror_positions(positions)
        positions = smooth_positions(positions)

        # Normalize camera direction (handles mirror / side-angle videos)
        forward_dx = positions[-1][0] - positions[0][0]
        camera_sign = 1 if forward_dx >= 0 else -1

        pitch_idx = self._detect_pitch_index(positions)
        if pitch_idx is None:
            return None

        pre_vec = (positions[pitch_idx - 2], positions[pitch_idx - 1])
        post_vec = (positions[pitch_idx + 1], positions[pitch_idx + 3])

        angle_pre = self._line_angle(*pre_vec)
        angle_post = self._line_angle(*post_vec)

        swing_angle = (angle_post - angle_pre) * camera_sign
        return round(float(swing_angle), 2)

def classify_swing(swing_deg):
    """
    Cricket-realistic classification.
    """
    if swing_deg is None:
        return "unknown"
    if abs(swing_deg) < 1.0:
        return "straight"
    return "inswing" if swing_deg < 0 else "outswing"

def calculate_swing(ball_positions):
    detector = SwingDetector()
    return classify_swing(detector.detect_swing(ball_positions))

def calculate_swing_name(ball_positions):
    return calculate_swing(ball_positions)

def calculate_swing_full(ball_positions):
    detector = SwingDetector()
    swing_deg = detector.detect_swing(ball_positions)

    if swing_deg is None:
        return {
            "swing": "unknown",
            "swing_degree": None
        }

    return {
        "swing": classify_swing(swing_deg),
        "swing_degree": swing_deg
    }