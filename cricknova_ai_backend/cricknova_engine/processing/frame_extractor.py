import cv2

def extract_frames(video_path, max_frames=120):
    frames = []
    cap = cv2.VideoCapture(video_path)

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frames.append(frame)
        if len(frames) >= max_frames:
            break

    cap.release()
    return frames