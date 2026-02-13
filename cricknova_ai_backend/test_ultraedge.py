from ultraedge.main import run_ultraedge
import sys
import os

def detect_stump_hit_from_positions(ball_positions, frame_width, frame_height):
    """
    Improved ICC-style stump detection with simple forward projection.
    Returns (hit: bool, confidence: float)
    """

    if not ball_positions or len(ball_positions) < 5:
        return False, 0.0

    # Slightly wider realistic stump zone
    stump_x_min = frame_width * 0.45
    stump_x_max = frame_width * 0.55
    stump_y_min = frame_height * 0.60
    stump_y_max = frame_height * 0.92

    # 1️⃣ Direct hit check (last frames)
    direct_hits = 0
    for (x, y) in ball_positions[-10:]:
        if stump_x_min <= x <= stump_x_max and stump_y_min <= y <= stump_y_max:
            direct_hits += 1

    if direct_hits >= 2:
        confidence = min(direct_hits / 4.0, 1.0)
        return True, round(confidence, 2)

    # 2️⃣ Simple linear projection (LBW cases)
    p1 = ball_positions[-3]
    p2 = ball_positions[-1]

    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]

    # Avoid division issues
    if abs(dy) < 1e-5:
        return False, 0.0

    # Project forward toward stump height
    target_y = stump_y_min
    t = (target_y - p2[1]) / dy

    projected_x = p2[0] + dx * t

    if stump_x_min <= projected_x <= stump_x_max:
        return True, 0.6  # moderate confidence projection

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