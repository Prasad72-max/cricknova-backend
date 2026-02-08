import cv2
import numpy as np
import math

from cricknova_engine.processing.speed import calculate_ball_speed_kmph as _speed_core

MAX_EFFECTIVE_DISTANCE_METERS = 23.0  # max real ball travel (release → bat)

def track_ball_positions(video_path, max_frames=120):
    cap = cv2.VideoCapture(video_path)

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps is None or fps <= 1 or fps > 240:
        fps = 30.0
    fps = float(fps)
    fps = min(max(fps, 24.0), 60.0)

    positions = []
    last_pos = None
    prev_gray = None
    frame_count = 0
    miss_count = 0

    TARGET_WIDTH = 640

    while cap.isOpened() and frame_count < max_frames:
        ret, frame = cap.read()
        if not ret:
            break

        frame_count += 1

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
        min_dist = float("inf")

        for c in contours:
            area = cv2.contourArea(c)
            if 18 < area < 900:
                (x, y, w, h) = cv2.boundingRect(c)
                cx = x + w // 2
                cy = y + h // 2

                if last_pos is None:
                    ball_candidate = (cx, cy)
                    break
                else:
                    dist = math.hypot(cx - last_pos[0], cy - last_pos[1])
                    if 1.2 < dist < min_dist:
                        min_dist = dist
                        ball_candidate = (cx, cy)

        if ball_candidate is None:
            miss_count += 1
            prev_gray = gray
            continue
        else:
            miss_count = 0
            positions.append(ball_candidate)
            last_pos = ball_candidate

        prev_gray = gray

        if len(positions) >= 12:
            break

    cap.release()
    return positions, fps


def calculate_ball_speed_kmph(positions, fps):
    """
    Delegates bowling speed calculation to processing.speed.
    Single source of truth for all speed logic.
    """
    return _speed_core(positions, fps)


def calculate_swing_type(positions):
    if not positions or len(positions) < 6:
        return "none"

    xs = [p[0] for p in positions]
    early_mean = np.mean(xs[: len(xs)//3])
    late_mean = np.mean(xs[-len(xs)//3 :])
    dx = late_mean - early_mean

    if abs(dx) < 6:
        return "none"
    return "inswing" if dx < 0 else "outswing"


def calculate_spin_type(positions):
    if not positions or len(positions) < 8:
        return "none"

    ys = [p[1] for p in positions]
    pitch_idx = int(np.argmax(ys))

    if pitch_idx >= len(positions) - 4:
        return "none"

    xs_after = [positions[i][0] for i in range(pitch_idx, len(positions))]
    drift = xs_after[-1] - xs_after[0]

    if abs(drift) < 5:
        return "none"
    return "off spin" if drift < 0 else "leg spin"