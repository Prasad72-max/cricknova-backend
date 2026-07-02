import math
import os
import time
from pathlib import Path
from threading import Lock

import cv2
import numpy as np

os.environ.setdefault("YOLO_CONFIG_DIR", "/tmp/Ultralytics")

_MODEL_LOCK = Lock()
_BALL_MODEL = None
_MODEL_LOAD_ATTEMPTED = False


def _default_model_path():
    backend_root = Path(__file__).resolve().parents[2]
    return backend_root / "models" / "cricket_ball_best.pt"


def _get_ball_model():
    global _BALL_MODEL, _MODEL_LOAD_ATTEMPTED
    if _MODEL_LOAD_ATTEMPTED:
        return _BALL_MODEL
    with _MODEL_LOCK:
        if _MODEL_LOAD_ATTEMPTED:
            return _BALL_MODEL
        _MODEL_LOAD_ATTEMPTED = True
        model_path = Path(os.getenv("CRICKNOVA_BALL_MODEL_PATH", str(_default_model_path())))
        try:
            from ultralytics import YOLO

            if not model_path.is_file():
                raise FileNotFoundError(f"Ball model not found: {model_path}")
            _BALL_MODEL = YOLO(str(model_path))
            print(f"BALL_TRACKER_MODEL_LOADED: {model_path}")
        except Exception as exc:
            print(f"BALL_TRACKER_MODEL_UNAVAILABLE: {exc}")
            _BALL_MODEL = None
        return _BALL_MODEL


def _ball_candidates(result, minimum_confidence):
    candidates = []
    names = getattr(result, "names", {}) or {}
    for box in result.boxes or []:
        class_id = int(box.cls[0])
        confidence = float(box.conf[0])
        label = str(names.get(class_id, "")).strip().lower()
        if label and label not in {"ball", "cricket ball", "-"}:
            continue
        if confidence < minimum_confidence:
            continue
        x1, y1, x2, y2 = box.xyxy[0].cpu().tolist()
        candidates.append(
            {
                "x": (float(x1) + float(x2)) / 2.0,
                "y": (float(y1) + float(y2)) / 2.0,
                "confidence": confidence,
                "box_area": max(0.0, (float(x2) - float(x1)) * (float(y2) - float(y1))),
            }
        )
    return candidates


def _new_kalman(x, y):
    kalman = cv2.KalmanFilter(4, 2)
    kalman.measurementMatrix = np.array([[1, 0, 0, 0], [0, 1, 0, 0]], dtype=np.float32)
    kalman.transitionMatrix = np.array(
        [[1, 0, 1, 0], [0, 1, 0, 1], [0, 0, 1, 0], [0, 0, 0, 1]],
        dtype=np.float32,
    )
    kalman.processNoiseCov = np.diag([0.03, 0.03, 0.28, 0.28]).astype(np.float32)
    kalman.measurementNoiseCov = np.eye(2, dtype=np.float32) * 0.55
    kalman.errorCovPost = np.eye(4, dtype=np.float32)
    kalman.statePost = np.array([[x], [y], [0], [0]], dtype=np.float32)
    return kalman


def _set_dt(kalman, dt):
    kalman.transitionMatrix = np.array(
        [[1, 0, dt, 0], [0, 1, 0, dt], [0, 0, 1, 0], [0, 0, 0, 1]],
        dtype=np.float32,
    )


def _motion_candidates(previous_gray, gray, width, height):
    diff = cv2.absdiff(previous_gray, gray)
    diff = cv2.GaussianBlur(diff, (5, 5), 0)
    _, mask = cv2.threshold(diff, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    kernel = np.ones((3, 3), np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    frame_area = float(width * height)
    min_area = max(3.0, frame_area * 0.000006)
    max_area = max(min_area + 1.0, frame_area * 0.004)
    candidates = []
    for contour in contours:
        area = float(cv2.contourArea(contour))
        if area < min_area or area > max_area:
            continue
        x, y, w, h = cv2.boundingRect(contour)
        if w <= 1 or h <= 1:
            continue
        aspect = max(w / float(h), h / float(w))
        if aspect > 3.2:
            continue
        moments = cv2.moments(contour)
        if abs(moments["m00"]) > 1e-9:
            cx = moments["m10"] / moments["m00"]
            cy = moments["m01"] / moments["m00"]
        else:
            cx = x + w / 2.0
            cy = y + h / 2.0
        candidates.append(
            {
                "x": float(cx),
                "y": float(cy),
                "confidence": float(min(0.62, 0.22 + (area / max_area) * 0.4)),
                "box_area": area,
            }
        )
    return candidates


def _track_motion_observations(video_path, max_frames=420):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return []

    observations = []
    frame_index = 0
    previous_gray = None
    previous = None
    previous_frame = None
    velocity = None
    kalman = None
    kalman_frame = None
    max_points = max(12, int(os.getenv("CRICKNOVA_BALL_MAX_POINTS", "120")))
    target_width = max(480, int(os.getenv("CRICKNOVA_MOTION_FRAME_WIDTH", "720")))
    deadline = time.monotonic() + max(8.0, float(os.getenv("CRICKNOVA_BALL_MAX_SECONDS", "45")))

    try:
        while cap.isOpened() and frame_index < max_frames:
            if time.monotonic() >= deadline:
                break
            ok, frame = cap.read()
            if not ok:
                break
            height, width = frame.shape[:2]
            if width <= 0 or height <= 0:
                frame_index += 1
                continue

            scale = min(1.0, target_width / float(width))
            small = cv2.resize(frame, (max(1, int(width * scale)), max(1, int(height * scale))))
            gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
            gray = cv2.GaussianBlur(gray, (5, 5), 0)

            if previous_gray is None:
                previous_gray = gray
                frame_index += 1
                continue

            candidates = _motion_candidates(previous_gray, gray, gray.shape[1], gray.shape[0])
            previous_gray = gray
            if not candidates:
                frame_index += 1
                continue

            for item in candidates:
                item["x"] /= scale
                item["y"] /= scale
                item["box_area"] /= max(scale * scale, 1e-9)

            if previous is None:
                selected = max(candidates, key=lambda item: item["confidence"])
            else:
                expected = previous
                if kalman is not None and kalman_frame is not None:
                    dt = max(1, frame_index - kalman_frame)
                    _set_dt(kalman, dt)
                    prediction = kalman.predict()
                    expected = (float(prediction[0, 0]), float(prediction[1, 0]))
                    kalman_frame = frame_index
                elif velocity is not None and previous_frame is not None:
                    dt = frame_index - previous_frame
                    expected = (previous[0] + velocity[0] * dt, previous[1] + velocity[1] * dt)

                selected = min(
                    candidates,
                    key=lambda item: math.hypot(item["x"] - expected[0], item["y"] - expected[1])
                    - (item["confidence"] * 35.0),
                )

            raw_x, raw_y = float(selected["x"]), float(selected["y"])
            if kalman is None:
                kalman = _new_kalman(raw_x, raw_y)
                kalman_frame = frame_index
                smoothed = (raw_x, raw_y)
            else:
                corrected = kalman.correct(np.array([[raw_x], [raw_y]], dtype=np.float32))
                smoothed = (float(corrected[0, 0]), float(corrected[1, 0]))

            if previous is not None and previous_frame is not None:
                frame_gap = frame_index - previous_frame
                if frame_gap > 0:
                    velocity = ((smoothed[0] - previous[0]) / frame_gap, (smoothed[1] - previous[1]) / frame_gap)

            observations.append(
                {
                    "frame": frame_index,
                    "x": smoothed[0],
                    "y": smoothed[1],
                    "confidence": round(float(selected["confidence"]), 4),
                    "interpolated": False,
                    "source": "motion_fallback",
                    "raw_x": round(raw_x, 3),
                    "raw_y": round(raw_y, 3),
                }
            )
            previous = smoothed
            previous_frame = frame_index
            frame_index += 1
            if len(observations) >= max_points:
                break
    finally:
        cap.release()

    return observations


def track_ball_observations(video_path, max_frames=420):
    model = _get_ball_model()
    if model is None:
        return _track_motion_observations(video_path, max_frames)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return []

    observations = []
    frame_index = 0
    previous = None
    previous_frame = None
    previous_confidence = None
    velocity = None
    kalman = None
    kalman_frame = None
    tracking_started = False
    misses_after_start = 0

    minimum_confidence = float(os.getenv("CRICKNOVA_BALL_CONF", "0.25"))
    search_stride = max(1, int(os.getenv("CRICKNOVA_BALL_SEARCH_STRIDE", "1")))
    inference_size = max(320, int(os.getenv("CRICKNOVA_BALL_IMGSZ", "640")))
    target_width = max(640, int(os.getenv("CRICKNOVA_BALL_FRAME_WIDTH", "960")))
    max_points = max(12, int(os.getenv("CRICKNOVA_BALL_MAX_POINTS", "120")))
    interpolation_gap = max(0, int(os.getenv("CRICKNOVA_INTERPOLATE_MAX_GAP", "8")))
    deadline = time.monotonic() + max(8.0, float(os.getenv("CRICKNOVA_BALL_MAX_SECONDS", "45")))

    try:
        while cap.isOpened() and frame_index < max_frames:
            if time.monotonic() >= deadline:
                break
            ok, frame = cap.read()
            if not ok:
                break
            height, width = frame.shape[:2]
            if width <= 0 or height <= 0:
                frame_index += 1
                continue

            if not tracking_started and frame_index % search_stride != 0:
                frame_index += 1
                continue

            scale = target_width / float(width)
            resized = cv2.resize(frame, (target_width, max(1, int(height * scale))))
            result = model.predict(
                source=resized,
                imgsz=inference_size,
                conf=minimum_confidence,
                iou=0.5,
                max_det=8,
                verbose=False,
            )[0]
            candidates = _ball_candidates(result, minimum_confidence)

            if candidates:
                tracking_started = True
                misses_after_start = 0
                for item in candidates:
                    item["x"] /= scale
                    item["y"] /= scale
                    item["box_area"] /= max(scale * scale, 1e-9)

                if previous is None:
                    selected = max(candidates, key=lambda item: item["confidence"])
                else:
                    expected = previous
                    if kalman is not None and kalman_frame is not None:
                        dt = max(1, frame_index - kalman_frame)
                        _set_dt(kalman, dt)
                        prediction = kalman.predict()
                        expected = (float(prediction[0, 0]), float(prediction[1, 0]))
                        kalman_frame = frame_index
                    elif velocity is not None and previous_frame is not None:
                        dt = frame_index - previous_frame
                        expected = (previous[0] + velocity[0] * dt, previous[1] + velocity[1] * dt)

                    selected = min(
                        candidates,
                        key=lambda item: math.hypot(item["x"] - expected[0], item["y"] - expected[1])
                        - (item["confidence"] * 45.0),
                    )

                raw_x, raw_y = float(selected["x"]), float(selected["y"])
                confidence = float(selected["confidence"])
                if kalman is None:
                    kalman = _new_kalman(raw_x, raw_y)
                    kalman_frame = frame_index
                    smoothed = (raw_x, raw_y)
                else:
                    corrected = kalman.correct(np.array([[raw_x], [raw_y]], dtype=np.float32))
                    smoothed = (float(corrected[0, 0]), float(corrected[1, 0]))

                if previous is not None and previous_frame is not None:
                    frame_gap = frame_index - previous_frame
                    if 1 < frame_gap <= interpolation_gap:
                        for step in range(1, frame_gap):
                            ratio = step / frame_gap
                            observations.append(
                                {
                                    "frame": previous_frame + step,
                                    "x": previous[0] + (smoothed[0] - previous[0]) * ratio,
                                    "y": previous[1] + (smoothed[1] - previous[1]) * ratio,
                                    "confidence": round(min(previous_confidence or confidence, confidence) * 0.82, 4),
                                    "interpolated": True,
                                    "source": "yolo_interpolated",
                                }
                            )
                    if frame_gap > 0:
                        velocity = ((smoothed[0] - previous[0]) / frame_gap, (smoothed[1] - previous[1]) / frame_gap)

                observations.append(
                    {
                        "frame": frame_index,
                        "x": smoothed[0],
                        "y": smoothed[1],
                        "confidence": round(confidence, 4),
                        "interpolated": False,
                        "source": "yolo",
                        "raw_x": round(raw_x, 3),
                        "raw_y": round(raw_y, 3),
                    }
                )
                previous = smoothed
                previous_frame = frame_index
                previous_confidence = confidence
            elif tracking_started:
                misses_after_start += 1
                if kalman is not None and kalman_frame is not None:
                    dt = max(1, frame_index - kalman_frame)
                    _set_dt(kalman, dt)
                    kalman.predict()
                    kalman_frame = frame_index
                if len(observations) >= 6 and misses_after_start >= 14:
                    break

            frame_index += 1
            if len(observations) >= max_points:
                break
    finally:
        cap.release()

    if len(observations) < 5 and os.getenv("CRICKNOVA_DISABLE_MOTION_FALLBACK", "0") != "1":
        fallback = _track_motion_observations(video_path, max_frames)
        if len(fallback) > len(observations):
            return fallback

    return observations


def track_ball_positions(video_path, max_frames=420):
    return [(item["x"], item["y"]) for item in track_ball_observations(video_path, max_frames)]
