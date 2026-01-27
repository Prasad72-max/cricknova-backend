import math
import numpy as np

def unmirror_positions(positions):
    """
    Fix horizontal camera mirroring from mobile videos.
    """
    xs = [p[0] for p in positions]
    min_x, max_x = min(xs), max(xs)

    return [((max_x - (x - min_x)), y) for x, y in positions]

class SwingDetector:

    def __init__(self, fps=30):
        self.fps = fps

    def _line_angle(self, p1, p2):
        """
        Returns angle of line (deg) between 2 points.
        """
        x1, y1 = p1
        x2, y2 = p2

        dx = x2 - x1
        dy = y2 - y1

        if dx == 0:
            return 90.0

        angle = math.degrees(math.atan2(dy, dx))
        return angle

    def detect_swing(self, positions):
        """
        positions: list of (x, y) from ball_tracker.

        Returns:
            float swing_angle_deg - numeric degrees of swing angle
        """
        if not positions or len(positions) < 8:
            return None

        # Fix mirrored camera coordinates before angle calculation
        positions = unmirror_positions(positions)

        # Detect pitch using maximum vertical acceleration (more stable)
        diffs = [positions[i+1][1] - positions[i][1] for i in range(len(positions)-1)]
        accel = [abs(diffs[i+1] - diffs[i]) for i in range(len(diffs)-1)]
        pitch_index = np.argmax(accel)

        # protect boundaries
        pitch_index = max(1, min(pitch_index, len(positions)-2))

        # pre-bounce (frames before pitch)
        pre1 = positions[pitch_index - 2]
        pre2 = positions[pitch_index - 1]

        # post-bounce (frames after pitch)
        post1 = positions[pitch_index + 1]
        post2 = positions[pitch_index + 3] if pitch_index + 3 < len(positions) else positions[-1]

        # Calculate angles
        angle_pre = self._line_angle(pre1, pre2)
        angle_post = self._line_angle(post1, post2)

        swing_angle = angle_post - angle_pre

        # Clamp swing to realistic cricket range (-8° to +8°)
        swing_angle = max(min(swing_angle, 8.0), -8.0)

        return round(swing_angle, 2)

def calculate_swing(ball_positions):
    """
    Returns ONLY swing name: inswing / outswing / straight
    """
    detector = SwingDetector()
    swing_deg = detector.detect_swing(ball_positions)
    if swing_deg is None:
        return "unknown"
    return classify_swing(swing_deg)

def calculate_swing_name(ball_positions):
    """
    Explicit helper to return ONLY swing name.
    """
    detector = SwingDetector()
    swing_deg = detector.detect_swing(ball_positions)
    if swing_deg is None:
        return "unknown"
    return classify_swing(swing_deg)

def classify_swing(swing_deg: float):
    """
    Cricket-correct swing classification after unmirroring.
    """
    if abs(swing_deg) < 1.2:
        return "straight"

    # NOTE:
    # Positive angle after unmirror = ball moves AWAY from body
    # Negative angle = ball moves INTO body

    if swing_deg < 0:
        return "inswing"
    else:
        return "outswing"
    return "straight"

def calculate_swing_full(ball_positions):
    """
    Returns swing data without confidence or labels.
    Output:
    {
        "swing": inswing / outswing / straight,
        "swing_degree": float
    }
    """
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