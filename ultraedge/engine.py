from .audio_processing import load_audio
from .waveform_builder import generate_waveform
from .spike_detector import detect_spikes

class UltraEdgeEngine:

    def __init__(self, threshold=0.2):
        self.threshold = threshold

    def analyze(self, audio_path):
        audio, sr = load_audio(audio_path)

        # Waveform for UI
        waveform_points, sr = generate_waveform(audio, sr)

        # Spike detection
        spikes = detect_spikes(audio, sr, threshold=self.threshold)

        hit_detected = len(spikes) > 0

        return {
            "waveform": {
                "sample_rate": sr,
                "points": waveform_points
            },
            "spikes": spikes,
            "hit_detected": hit_detected
        }