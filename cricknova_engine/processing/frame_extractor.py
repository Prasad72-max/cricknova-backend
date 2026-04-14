import cv2
import numpy as np

def extract_frames(video_path, max_frames=120):
    """
    Extract evenly spaced frames across the FULL video duration.
    This prevents early-frame bias and improves swing/spin detection.
    """

    frames = []
    cap = cv2.VideoCapture(video_path)

    if not cap.isOpened():
        return frames

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    if total_frames <= 0:
        cap.release()
        return frames

    # If video shorter than max_frames → read normally
    if total_frames <= max_frames:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            frames.append(frame)
        cap.release()
        return frames

    # Otherwise sample evenly across full video
    indices = np.linspace(0, total_frames - 1, max_frames).astype(int)

    for idx in indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ret, frame = cap.read()
        if ret:
            frames.append(frame)

    cap.release()
    return frames