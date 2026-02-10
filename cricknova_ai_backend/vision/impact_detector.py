"""
Impact detection module for CrickNova Vision.
Determines whether the ball contacted bat, pad, or stumps using trajectory + audio/visual cues.
This feeds directly into DRS OUT / NOT OUT decisions.
"""

from typing import Dict, List, Tuple
import math

# Thresholds (tuned for mobile-recorded cricket videos)
BAT_EDGE_DISTANCE_PX = 12      # proximity to bat edge
PAD_DISTANCE_PX = 18           # proximity to pad region
STUMP_DISTANCE_PX = 15         # proximity to stump center
ANGLE_CHANGE_THRESHOLD = 12.0  # degrees, sudden deflection


def _angle(v1: Tuple[float, float], v2: Tuple[float, float]) -> float:
    """Return angle between two vectors in degrees."""
    dot = v1[0]*v2[0] + v1[1]*v2[1]
    mag1 = math.hypot(v1[0], v1[1])
    mag2 = math.hypot(v2[0], v2[1])
    if mag1 == 0 or mag2 == 0:
        return 0.0
    cos_theta = max(min(dot / (mag1 * mag2), 1), -1)
    return math.degrees(math.acos(cos_theta))


def detect_impact(
    trajectory: List[Tuple[float, float]],
    bat_points: List[Tuple[float, float]] = None,
    pad_points: List[Tuple[float, float]] = None,
    stump_points: List[Tuple[float, float]] = None,
) -> Dict:
    """
    Detect the most likely impact event.

    Returns:
        {
          "impact": "BAT" | "PAD" | "STUMP" | "NONE",
          "confidence": float
        }
    """
    if trajectory is None or len(trajectory) < 3:
        return {"impact": "NONE", "confidence": 0.0}

    bat_points = bat_points or []
    pad_points = pad_points or []
    stump_points = stump_points or []

    # Compute angle change at mid trajectory
    p_prev = trajectory[-3]
    p_hit = trajectory[-2]
    p_next = trajectory[-1]

    v1 = (p_hit[0] - p_prev[0], p_hit[1] - p_prev[1])
    v2 = (p_next[0] - p_hit[0], p_next[1] - p_hit[1])

    angle_change = _angle(v1, v2)

    # Helper to compute min distance
    def min_dist(p, points):
        return min((math.hypot(p[0]-q[0], p[1]-q[1]) for q in points), default=1e9)

    # Distances
    d_bat = min_dist(p_hit, bat_points)
    d_pad = min_dist(p_hit, pad_points)
    d_stump = min_dist(p_hit, stump_points)

    # Decision logic (priority order)
    if d_stump <= STUMP_DISTANCE_PX:
        return {"impact": "STUMP", "confidence": 0.95}

    if d_bat <= BAT_EDGE_DISTANCE_PX and angle_change >= ANGLE_CHANGE_THRESHOLD:
        return {"impact": "BAT", "confidence": min(0.9, angle_change / 30)}

    if d_pad <= PAD_DISTANCE_PX:
        return {"impact": "PAD", "confidence": 0.75}

    return {"impact": "NONE", "confidence": 0.2}


__all__ = ["detect_impact"]
