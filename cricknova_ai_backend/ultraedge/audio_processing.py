import soundfile as sf
import numpy as np

def load_audio(path):
    """
    Loads audio from a WAV file.
    Returns audio array and sample rate.
    """
    audio, sr = sf.read(path)

    # Convert stereo → mono if needed
    if len(audio.shape) > 1:
        audio = np.mean(audio, axis=1)

    return audio, sr

def normalize_audio(audio):
    """
    Normalize audio to -1 to 1 range for stable UltraEdge detection.
    """
    max_val = np.max(np.abs(audio))
    if max_val == 0:
        return audio
    return audio / max_val


def high_pass_filter(audio, sr, cutoff=2000):
    """
    Simple high-pass filter to isolate bat/pad edge frequencies.
    """
    from scipy.signal import butter, filtfilt

    nyq = 0.5 * sr
    norm_cutoff = cutoff / nyq
    b, a = butter(3, norm_cutoff, btype='high', analog=False)
    return filtfilt(b, a, audio)


def preprocess_ultraedge_audio(path):
    """
    Full UltraEdge audio preprocessing pipeline:
    - load
    - mono
    - normalize
    - high-pass filter (edge isolation)
    """
    audio, sr = load_audio(path)
    audio = normalize_audio(audio)
    audio = high_pass_filter(audio, sr)
    return audio, sr