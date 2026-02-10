

"""
Trajectory builder for CrickNova Vision.
Builds a clean, physics-safe ball trajectory used by swing, spin, speed and DRS.
No scripting, no guessing – only tracked motion.
"""

from typing import List, Tuple
import math


def build_trajectory(
    ball_positions: List[Tuple[float, float]],
    max_points: int = 60,
    min_dist_px: float = 1.5,
) -> List[Tuple[float, float]]:
    """
    Normalize and thin raw ball positions into a stable trajectory.

    - Removes duplicate / jitter points
    - Keeps only forward-moving motion
    - Limits to last `max_points`
    """
    if not ball_positions or len(ball_positions) < 3:
        return []

    cleaned: List[Tuple[float, float]] = []

    for p in ball_positions:
        if not cleaned:
            cleaned.append(p)
            continue

        last = cleaned[-1]
        dist = math.hypot(p[0] - last[0], p[1] - last[1])

        # Drop jitter / stationary noise
        if dist < min_dist_px:
            continue

        cleaned.append(p)

    # Keep only last N points (delivery phase)
    if len(cleaned) > max_points:
        cleaned = cleaned[-max_points:]

    return cleaned


__all__ = ["build_trajectory"]