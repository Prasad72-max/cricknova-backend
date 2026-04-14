import numpy as np

def detect_spikes(audio, sr, threshold=2.8, window_ms=8, band=(1500, 6000)):
    """
    Improved physics-based UltraEdge spike detection.

    Improvements:
    - Slightly more sensitive default threshold
    - Uses median-based robust baseline
    - Adaptive threshold scaling
    - Returns list of spike sample indices
    """

    if audio is None or len(audio) == 0 or sr <= 0:
        return []

    audio = audio.astype(np.float32)

    window_size = max(16, int((window_ms / 1000.0) * sr))
    hop = window_size
    spikes = []

    band_low, band_high = band
    freqs = np.fft.rfftfreq(window_size, d=1.0 / sr)
    band_mask = (freqs >= band_low) & (freqs <= band_high)

    band_energies = []

    # --- pass 1: compute band energy per window ---
    for i in range(0, len(audio) - window_size, hop):
        segment = audio[i:i + window_size]

        if np.allclose(segment, 0):
            band_energies.append(0.0)
            continue

        windowed = segment * np.hanning(len(segment))
        spectrum = np.abs(np.fft.rfft(windowed))
        band_energy = float(np.mean(spectrum[band_mask])) if np.any(band_mask) else 0.0
        band_energies.append(band_energy)

    if len(band_energies) < 6:
        return []

    energies = np.array(band_energies)

    # Robust baseline using median instead of mean
    baseline = float(np.median(energies))
    deviation = float(np.std(energies)) + 1e-6

    # Adaptive scaling for noisy recordings
    adaptive_threshold = threshold * (1.0 + deviation / (baseline + 1e-6))

    # --- pass 2: adaptive z-score thresholding ---
    for idx, e in enumerate(energies):
        z = (e - baseline) / deviation
        if z >= adaptive_threshold:
            spikes.append(idx * hop)

    return spikes