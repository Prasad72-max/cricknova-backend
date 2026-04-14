import numpy as np

def detect_spikes(audio, sr, threshold=3.5, window_ms=8, band=(1500, 6000)):
    """
    Physics-based UltraEdge spike detection (non-scripted).

    How it works:
    - Short-time windows (8 ms default)
    - Band-limited energy (bat impact frequencies ~1.5–6 kHz)
    - Z-score on band energy to detect true transients
    - Returns list of sample indices where a spike is detected

    Params:
    - audio: 1D numpy array (mono, float)
    - sr: sample rate (Hz)
    - threshold: z-score threshold (higher = stricter)
    - window_ms: analysis window in milliseconds
    - band: (low_hz, high_hz) frequency band for bat impact
    """

    if audio is None or len(audio) == 0 or sr <= 0:
        return []

    # Ensure float32 for stable FFT
    audio = audio.astype(np.float32)

    window_size = max(16, int((window_ms / 1000.0) * sr))
    hop = window_size
    spikes = []

    band_low, band_high = band
    freqs = np.fft.rfftfreq(window_size, d=1.0/sr)
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
    mean_e = float(np.mean(energies))
    std_e = float(np.std(energies)) + 1e-6

    # --- pass 2: z-score thresholding ---
    for idx, e in enumerate(energies):
        z = (e - mean_e) / std_e
        if z >= threshold:
            spikes.append(idx * hop)

    return spikes