

"""
Stump model for CrickNova Vision.
Provides geometric stump zone and hit detection used by DRS.
"""

from typing import List, Tuple, Dict
import math

# Approximate stump geometry (normalized / pixel-space tolerant)
STUMP_WIDTH_PX = 22     # total width of 3 stumps
STUMP_HEIGHT_PX = 71    # visible stump height


def stump_zone(center: Tuple[float, float]) -> List[Tuple[float, float]]:
    """
    Return rectangular stump zone corners given stump center.
    """
    cx, cy = center
    half_w = STUMP_WIDTH_PX / 2
    half_h = STUMP_HEIGHT_PX / 2
    return [
        (cx - half_w, cy - half_h),
        (cx + half_w, cy - half_h),
        (cx + half_w, cy + half_h),
        (cx - half_w, cy + half_h),
    ]


def _point_in_rect(p: Tuple[float, float], rect: List[Tuple[float, float]]) -> bool:
    xs = [r[0] for r in rect]
    ys = [r[1] for r in rect]
    return min(xs) <= p[0] <= max(xs) and min(ys) <= p[1] <= max(ys)


def detect_stump_hit(
    trajectory: List[Tuple[float, float]],
    stump_center: Tuple[float, float],
) -> Dict:
    """
    Detect whether trajectory intersects stump zone.

    Returns:
        {"hit": bool, "confidence": float}
    """
    if not trajectory or len(trajectory) < 2:
        return {"hit": False, "confidence": 0.0}

    zone = stump_zone(stump_center)

    for p in trajectory[-5:]:  # check last few points
        if _point_in_rect(p, zone):
            return {"hit": True, "confidence": 0.97}

    return {"hit": False, "confidence": 0.1}


__all__ = ["stump_zone", "detect_stump_hit"]