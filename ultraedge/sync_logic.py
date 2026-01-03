

"""
UltraEdge + Ball Path + Stump Sync Logic
Science-based DRS decision engine (NON-SCRIPTED)
"""

import numpy as np

def decide_drs(
    ultraedge_spikes: list,
    ball_trajectory: list,
    stump_polygon: list,
    edge_confidence_threshold: float = 0.6,
):
    """
    Parameters
    ----------
    ultraedge_spikes : list
        Output from UltraEdge detector (list of spike dicts)
        Example: [{"time": 0.432, "z": 6.1}]
    ball_trajectory : list
        Normalized ball path [{x, y}, ...]
    stump_polygon : list
        List of (x,y) points defining stump hit area (normalized)
    edge_confidence_threshold : float
        Minimum z-score confidence to confirm edge

    Returns
    -------
    dict
        {
          "decision": "OUT" | "NOT OUT",
          "reason": str,
          "edge_detected": bool,
          "stumps_hit": bool
        }
    """

    # -----------------------------
    # 1. UltraEdge decision
    # -----------------------------
    edge_detected = False
    if ultraedge_spikes:
        strongest = max(ultraedge_spikes, key=lambda s: s.get("z", 0))
        if strongest.get("z", 0) >= edge_confidence_threshold * 10:
            edge_detected = True

    # -----------------------------
    # 2. Stump intersection check
    # -----------------------------
    def point_in_polygon(x, y, poly):
        inside = False
        n = len(poly)
        px, py = zip(*poly)
        j = n - 1
        for i in range(n):
            if ((py[i] > y) != (py[j] > y)) and (
                x < (px[j] - px[i]) * (y - py[i]) / (py[j] - py[i] + 1e-6) + px[i]
            ):
                inside = not inside
            j = i
        return inside

    stumps_hit = False
    for p in ball_trajectory:
        if point_in_polygon(p["x"], p["y"], stump_polygon):
            stumps_hit = True
            break

    # -----------------------------
    # 3. Final DRS decision logic
    # -----------------------------
    if edge_detected:
        return {
            "decision": "NOT OUT",
            "reason": "UltraEdge confirmed bat contact",
            "edge_detected": True,
            "stumps_hit": stumps_hit,
        }

    if stumps_hit:
        return {
            "decision": "OUT",
            "reason": "No edge detected and ball hitting stumps",
            "edge_detected": False,
            "stumps_hit": True,
        }

    return {
        "decision": "NOT OUT",
        "reason": "No edge and ball missing stumps",
        "edge_detected": False,
        "stumps_hit": False,
    }