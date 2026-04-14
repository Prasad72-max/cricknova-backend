import cv2 as cv
import numpy as np
import math

def track_ball_positions(video_path):
    cap = cv.VideoCapture(video_path)
    ball_positions = []
    prev_center = None
    prev_direction = None
    frame_idx = 0

    backSub = cv.createBackgroundSubtractorMOG2(
        history=200,
        varThreshold=25,
        detectShadows=False
    )

    def distance(p1, p2):
        return math.hypot(p1[0] - p2[0], p1[1] - p2[1])

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        frame_idx += 1

        gray = cv.cvtColor(frame, cv.COLOR_BGR2GRAY)
        blur = cv.GaussianBlur(gray, (9, 9), 0)

        # --- Foreground motion mask ---
        fg_mask = backSub.apply(blur)
        fg_mask = cv.medianBlur(fg_mask, 5)

        contours, _ = cv.findContours(
            fg_mask, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE
        )

        candidates = []

        for cnt in contours:
            area = cv.contourArea(cnt)
            if 30 < area < 2500:
                (x, y), radius = cv.minEnclosingCircle(cnt)
                if 4 < radius < 30:
                    candidates.append((int(x), int(y)))

        chosen = None

        # --- Prefer contour-based motion ---
        if candidates:
            if prev_center:
                chosen = min(
                    candidates,
                    key=lambda c: distance(c, prev_center)
                )
            else:
                chosen = candidates[0]

        # --- Fallback to Hough if needed ---
        if chosen is None:
            circles = cv.HoughCircles(
                blur,
                cv.HOUGH_GRADIENT,
                dp=1.3,
                minDist=80,
                param1=120,
                param2=28,
                minRadius=6,
                maxRadius=30
            )

            if circles is not None:
                circles = np.uint16(np.around(circles))
                if prev_center:
                    chosen = min(
                        [(c[0], c[1]) for c in circles[0]],
                        key=lambda c: distance(c, prev_center)
                    )
                else:
                    chosen = (circles[0][0][0], circles[0][0][1])

        if chosen is not None:

            # Direction consistency filter
            if prev_center is not None:
                dx = chosen[0] - prev_center[0]
                dy = chosen[1] - prev_center[1]

                current_direction = (dx, dy)

                if prev_direction is not None:
                    dot = dx * prev_direction[0] + dy * prev_direction[1]

                    # If direction suddenly flips, ignore noisy jump
                    if dot < 0:
                        continue

                prev_direction = current_direction

            # Smooth trajectory (simple averaging to reduce jitter)
            if prev_center is not None:
                smoothed_x = int((chosen[0] + prev_center[0]) / 2)
                smoothed_y = int((chosen[1] + prev_center[1]) / 2)
                chosen = (smoothed_x, smoothed_y)

            ball_positions.append((chosen[0], chosen[1], frame_idx))
            prev_center = chosen

    cap.release()
    return ball_positions