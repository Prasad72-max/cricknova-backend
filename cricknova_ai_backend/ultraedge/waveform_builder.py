import numpy as np

def generate_waveform(audio, sr, max_points=500):
    """
    Generate UltraEdge-style waveform:
    - Use RMS energy (not raw waveform)
    - Emphasize sharp contact spikes (bat / pad)
    - Stable, TV-like output for frontend graph
    """

    if audio is None or len(audio) == 0:
        return [], sr

    # Ensure numpy array
    audio = np.asarray(audio, dtype=np.float32)

    # Window size ~2ms (UltraEdge-like)
    window_size = max(1, int(sr * 0.002))
    hop_size = window_size

    rms_values = []
    for i in range(0, len(audio) - window_size, hop_size):
        window = audio[i:i + window_size]
        rms = np.sqrt(np.mean(window ** 2))
        rms_values.append(rms)

    if not rms_values:
        return [], sr

    rms_values = np.array(rms_values)

    # Normalize (TV broadcast style)
    max_val = np.max(rms_values)
    if max_val > 0:
        rms_values = rms_values / max_val

    # Downsample for frontend
    step = max(1, len(rms_values) // max_points)
    waveform = rms_values[::step].tolist()

    return waveform, sr


def detect_ultraedge_spike(rms_waveform, threshold_factor=2.5):
    """
    Improved UltraEdge spike detection.
    - Uses adaptive baseline (median)
    - More realistic broadcast sensitivity
    - Returns (detected: bool, confidence: float)
    """

    if rms_waveform is None or len(rms_waveform) < 5:
        return False, 0.0

    data = np.asarray(rms_waveform, dtype=np.float32)

    baseline = np.median(data)
    max_val = np.max(data)

    if baseline <= 0:
        return False, 0.0

    spike_ratio = max_val / baseline

    # Confidence scaled between 0–1
    confidence = min(1.0, spike_ratio / (threshold_factor * 2.0))

    if spike_ratio >= threshold_factor:
        return True, round(confidence, 2)

    return False, round(confidence, 2)