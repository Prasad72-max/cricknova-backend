import cv2
import numpy as np
import math

def track_ball_positions(video_path, max_frames=60):
    cap = cv2.VideoCapture(video_path)

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps is None or fps <= 1:
        fps = 30.0

    positions = []
    prev_gray = None
    frame_count = 0

    # scale down once (huge speed boost)
    TARGET_WIDTH = 640

    while cap.isOpened() and frame_count < max_frames:
        ret, frame = cap.read()
        if not ret:
            break

        frame_count += 1

        # downscale frame
        h, w = frame.shape[:2]
        scale = TARGET_WIDTH / w
        frame = cv2.resize(frame, (TARGET_WIDTH, int(h * scale)))

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (7, 7), 0)

        if prev_gray is None:
            prev_gray = gray
            continue

        diff = cv2.absdiff(prev_gray, gray)
        _, thresh = cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)
        thresh = cv2.dilate(thresh, None, iterations=2)

        contours, _ = cv2.findContours(
            thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )

        ball_candidate = None
        max_area = 0

        for c in contours:
            area = cv2.contourArea(c)
            if 30 < area < 400 and area > max_area:
                (x, y, w, h) = cv2.boundingRect(c)
                cx = x + w // 2
                cy = y + h // 2
                ball_candidate = (cx, cy)
                max_area = area

        if ball_candidate:
            positions.append(ball_candidate)

        prev_gray = gray

        # stop early if enough points found
        if len(positions) >= 30:
            break

    cap.release()
    return positions