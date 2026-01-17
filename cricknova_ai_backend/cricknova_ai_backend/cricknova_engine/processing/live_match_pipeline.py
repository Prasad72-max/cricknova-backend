import cv2
import numpy as np

from .ball_tracker import BallTracker
from .trajectory import TrajectoryCalculator
from .release_point import ReleasePointDetector
from .shot_classifier import ShotClassifier


class LiveMatchPipeline:

    def __init__(self, debug=False, frame_skip=1):
        self.tracker = BallTracker()
        self.release = ReleasePointDetector()
        self.trajectory_calc = TrajectoryCalculator()
        self.classifier = ShotClassifier()

        self.debug = debug            # optional logs
        self.frame_skip = frame_skip  # skip frames for faster AI

    # --------------------------------------------------------
    # PROCESS FULL DELIVERY
    # --------------------------------------------------------
    def process_delivery(self, video_path):
        frames = self._load_video(video_path)

        if len(frames) < 10:
            return {"error": "Video too short"}

        # 1) TRACK BALL POSITIONS
        positions = self.tracker.track(frames, frame_skip=self.frame_skip)

        if len(positions) == 0:
            return {"error": "Ball tracker failed"}

        # 2) RELEASE POINT
        release_frame = self.release.detect(positions)

        # 3) CONTACT POINT
        contact_frame = self._estimate_contact(positions)

        if self.debug:
            print(f"[DEBUG] Release: {release_frame}, Contact: {contact_frame}")

        # 4) TRAJECTORY
        trajectory = self.trajectory_calc.compute(
            positions, release_frame, contact_frame
        )

        # 5) SHOT CLASSIFICATION
        shot, certainty = self.classifier.classify(
            trajectory, positions, contact_frame, return_prob=True
        )

        # 6) SPEEDS
        speed_before = self._speed(positions, contact_frame - 1, contact_frame - 2)
        speed_after = self._speed(positions, contact_frame + 1, contact_frame)

        # 7) DISTANCE
        distance = self._travel_distance(positions, contact_frame)

        # 8) ANGLE
        angle = trajectory["angle_deg"] if trajectory else None

        return {
            "shot": shot,
            "certainty": float(certainty),
            "contact_frame": int(contact_frame),
            "speed_before": float(speed_before),
            "speed_after": float(speed_after),
            "distance": float(distance),
            "angle": float(angle) if angle else None,
        }

    # --------------------------------------------------------
    # CONTACT ESTIMATION (improved)
    # --------------------------------------------------------
    def _estimate_contact(self, positions):
        speeds = []

        for i in range(1, len(positions)):
            if positions[i] is None or positions[i - 1] is None:
                speeds.append(0)
                continue

            p1 = np.array(positions[i])
            p2 = np.array(positions[i - 1])

            speeds.append(np.linalg.norm(p1 - p2))

        speeds = np.array(speeds)

        # smooth speeds
        speeds = np.convolve(speeds, np.ones(5) / 5, mode="same")

        diffs = np.abs(np.diff(speeds))
        if len(diffs) == 0:
            return 10

        return int(np.argmax(diffs))

    # --------------------------------------------------------
    # LOAD VIDEO
    # --------------------------------------------------------
    def _load_video(self, path):
        cap = cv2.VideoCapture(path)
        frames = []
        count = 0

        while True:
            ok, frame = cap.read()
            if not ok:
                break

            # apply frame skipping
            if count % self.frame_skip == 0:
                frames.append(frame)

            count += 1

        cap.release()

        return frames

    # --------------------------------------------------------
    # SPEED helper
    # --------------------------------------------------------
    def _speed(self, positions, f1, f2):
        if f1 < 0 or f2 < 0:
            return 0.0
        if positions[f1] is None or positions[f2] is None:
            return 0.0
        return float(np.linalg.norm(np.array(positions[f1]) - np.array(positions[f2])))

    # --------------------------------------------------------
    # DISTANCE helper
    # --------------------------------------------------------
    def _travel_distance(self, positions, contact_frame):
        if positions[contact_frame] is None:
            return 0.0

        total = 0.0
        prev = np.array(positions[contact_frame])

        for p in positions[contact_frame + 1:]:
            if p is None:
                break
            p = np.array(p)
            total += float(np.linalg.norm(p - prev))
            prev = p

        return total