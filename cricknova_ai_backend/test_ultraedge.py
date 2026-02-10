from ultraedge.main import run_ultraedge
import sys
import os

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

# Final DRS-style decision (REAL ICC FLOW)
# UltraEdge can NEVER force NOT OUT
# It only informs contact, decision comes from ball tracking / impact

contact_type = result.get("type", "").upper()

if contact_type == "BAT":
    print("DRS RESULT : 🟡 BAT CONTACT (Proceed to ball tracking)")

elif contact_type == "PAD":
    print("DRS RESULT : 🟡 PAD CONTACT (Proceed to LBW check)")

elif contact:
    print("DRS RESULT : 🟡 CONTACT DETECTED (Proceed to ball tracking)")

else:
    print("DRS RESULT : 🟡 NO CONTACT (Proceed to ball tracking)")

print("==========================\n")