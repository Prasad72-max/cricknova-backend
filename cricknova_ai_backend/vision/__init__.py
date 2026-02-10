

"""
Vision package bootstrap for CrickNova.
Ensures stable imports and corrects swing/spin direction mapping.
"""

# Public API flags
VISION_ENABLED = True

# Direction normalization helpers
# Positive X movement towards batter's off side should be OUTSWING for a right-hander
# Positive Y angular velocity (top-down camera) should be OFF SPIN

def normalize_swing(dx):
    """Return 'In Swing' or 'Out Swing' based on lateral delta dx."""
    try:
        return "Out Swing" if dx > 0 else "In Swing"
    except Exception:
        return "Unknown"


def normalize_spin(angular_vel):
    """Return spin label based on angular velocity sign."""
    try:
        return "Off Spin" if angular_vel > 0 else "Leg Spin"
    except Exception:
        return "Unknown"

# Safe optional imports (avoid crashing if modules are absent)
try:
    from .drs_engine import evaluate_drs  # noqa: F401
except Exception:
    def evaluate_drs(*args, **kwargs):
        return {"decision": "NOT OUT", "confidence": 0.0}

__all__ = [
    "VISION_ENABLED",
    "normalize_swing",
    "normalize_spin",
    "evaluate_drs",
]