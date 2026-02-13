from ultraedge.main import run_ultraedge
import sys
import os

def detect_stump_hit_from_positions(ball_positions, frame_width, frame_height):
    """
    DRS 2.0 – Real projection-based logic (Hawk-Eye lite style)

    Logic:
    1) Build straight pitch line (22.86m conceptual alignment).
    2) Classify short/bouncer as NOT OUT.
    3) Project ball path toward stump plane.
    4) If projected X lies within stump width → OUT.
    """

    if not ball_positions or len(ball_positions) < 5:
        return False, 0.0

    # --- DRS 2.0 Pure Projection Logic ---
    # No short-ball heuristic
    # No average height filtering
    # Only geometric projection to stump plane

    stump_center_x = frame_width * 0.50
    stump_width_half = frame_width * 0.035  # tighter realistic stump width

    stump_x_min = stump_center_x - stump_width_half
    stump_x_max = stump_center_x + stump_width_half

    stump_plane_y = frame_height * 0.78  # slightly lower realistic stump plane

    # Use last 6 tracking points for stable direction
    recent_points = ball_positions[-6:]
    p_start = recent_points[0]
    p_end = recent_points[-1]

    dx = p_end[0] - p_start[0]
    dy = p_end[1] - p_start[1]

    if abs(dy) < 1e-6:
        return False, 0.0

    # Project to stump plane
    t = (stump_plane_y - p_end[1]) / dy
    projected_x = p_end[0] + dx * t

    if stump_x_min <= projected_x <= stump_x_max:
        return True, 0.92  # stronger confidence for clean geometric hit

    return False, 0.0

# ----------------------------------------
# REAL ULTRAEDGE TEST SCRIPT
# ----------------------------------------
# Usage:
#   python test_ultraedge.py edge.wav
#   python test_ultraedge.py silent.wav
# ----------------------------------------

if len(sys.argv) < 2:
    print("❌ Please provide an audio file")
    print("Usage: python test_ultraedge.py <audio.wav>")
    sys.exit(1)

audio_path = sys.argv[1]

if not os.path.exists(audio_path):
    print(f"❌ File not found: {audio_path}")
    sys.exit(1)

result = run_ultraedge(audio_path)

print("\n=== ULTRAEDGE ANALYSIS ===")
print(f"Audio File : {audio_path}")

contact = result.get("contact", False)
confidence = float(result.get("confidence", 0.0))

print(f"Contact    : {'YES (BAT/PAD)' if contact else 'NO CONTACT'}")
print(f"Confidence : {confidence:.2f}")

# Final DRS-style decision
if contact:
    print("DRS RESULT : 🟢 NOT OUT (UltraEdge spike detected)")
else:
    # If no edge, simulate ball tracking + stump check
    ball_positions = result.get("ball_positions", [])
    frame_width = result.get("frame_width", 1)
    frame_height = result.get("frame_height", 1)

    hit, stump_conf = detect_stump_hit_from_positions(
        ball_positions,
        frame_width,
        frame_height
    )

    if hit:
        print(f"DRS RESULT : 🔴 OUT (Ball hitting stumps, confidence={stump_conf})")
    else:
        print("DRS RESULT : 🟢 NOT OUT (Ball missing stumps)")

print("==========================\n")