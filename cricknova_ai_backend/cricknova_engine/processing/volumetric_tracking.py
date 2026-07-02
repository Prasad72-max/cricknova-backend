"""
CrickNova AI 3D volumetric tracking core.

This module is intentionally independent from FastAPI so it can be tested with
notebooks, backend endpoints, or batch jobs. A single umpire-position camera can
recover metric X/Y on the pitch plane with homography. True absolute Z needs
stereo, radar, or known ball-size/camera intrinsics; here Z is reconstructed with
a physics prior and every export includes the method used.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Iterable

import cv2
import numpy as np
from filterpy.kalman import KalmanFilter
from scipy.interpolate import CubicSpline


PITCH_LENGTH_M = 20.12
PITCH_WIDTH_M = 3.05


@dataclass(frozen=True)
class PitchCalibrator:
    """Map clicked image pixels to real cricket-pitch meters."""

    image_points: np.ndarray
    pitch_length_m: float = PITCH_LENGTH_M
    pitch_width_m: float = PITCH_WIDTH_M
    matrix: np.ndarray | None = None

    @classmethod
    def from_points(
        cls,
        image_points: Iterable[Iterable[float]],
        pitch_length_m: float = PITCH_LENGTH_M,
        pitch_width_m: float = PITCH_WIDTH_M,
    ) -> "PitchCalibrator":
        points = np.asarray(list(image_points), dtype=np.float32)
        if points.shape != (4, 2):
            raise ValueError("Pitch calibration needs exactly 4 image points: [[u,v], ...].")

        # Expected order:
        # 0 near-left crease corner, 1 near-right crease corner,
        # 2 far-right crease corner, 3 far-left crease corner.
        #
        # The destination is a top-down pitch plane in meters:
        # X = lateral pitch width, Y = pitch length from camera/stumps to bowler.
        world_points = np.asarray(
            [
                [0.0, 0.0],
                [pitch_width_m, 0.0],
                [pitch_width_m, pitch_length_m],
                [0.0, pitch_length_m],
            ],
            dtype=np.float32,
        )

        # Homography solves a 3x3 projective matrix H where:
        # [x', y', w']^T = H * [u, v, 1]^T, then X = x'/w', Y = y'/w'.
        # This removes camera perspective for all points lying on the pitch plane.
        matrix = cv2.getPerspectiveTransform(points, world_points)
        return cls(points, pitch_length_m, pitch_width_m, matrix)

    def image_to_world(self, uv_points: Iterable[Iterable[float]]) -> np.ndarray:
        """Vectorized pixel-to-meter transform for Nx2 image points."""
        if self.matrix is None:
            raise ValueError("PitchCalibrator matrix is not initialized.")
        uv = np.asarray(list(uv_points), dtype=np.float32).reshape(-1, 1, 2)
        if uv.size == 0:
            return np.empty((0, 2), dtype=np.float32)
        xy = cv2.perspectiveTransform(uv, self.matrix).reshape(-1, 2)
        return xy.astype(np.float32)

    def to_json(self) -> dict[str, Any]:
        return {
            "pitch_length_m": self.pitch_length_m,
            "pitch_width_m": self.pitch_width_m,
            "image_points": self.image_points.astype(float).round(3).tolist(),
            "homography": np.asarray(self.matrix, dtype=float).round(8).tolist(),
        }


class BallTracker:
    """Constant-velocity Kalman tracker for frame-by-frame ball detections."""

    def __init__(
        self,
        fps: float,
        process_noise: float = 0.08,
        measurement_noise: float = 2.2,
        max_occlusion_frames: int = 10,
    ) -> None:
        self.fps = max(float(fps), 1.0)
        self.dt = 1.0 / self.fps
        self.max_occlusion_frames = int(max_occlusion_frames)
        self.kf = KalmanFilter(dim_x=4, dim_z=2)
        self.kf.F = np.array(
            [
                [1.0, 0.0, self.dt, 0.0],
                [0.0, 1.0, 0.0, self.dt],
                [0.0, 0.0, 1.0, 0.0],
                [0.0, 0.0, 0.0, 1.0],
            ],
            dtype=float,
        )
        self.kf.H = np.array([[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0]], dtype=float)
        self.kf.P *= 800.0
        self.kf.R = np.eye(2, dtype=float) * float(measurement_noise)
        self.kf.Q = np.diag([process_noise, process_noise, process_noise * 6.0, process_noise * 6.0])
        self.initialized = False
        self.missed_frames = 0

    def update(self, detection_uv: tuple[float, float] | None, frame: int) -> dict[str, Any] | None:
        """Update with a detection or predict through short occlusions."""
        if detection_uv is None and not self.initialized:
            return None

        if not self.initialized and detection_uv is not None:
            self.kf.x = np.array([[detection_uv[0]], [detection_uv[1]], [0.0], [0.0]], dtype=float)
            self.initialized = True
            self.missed_frames = 0
            return self._state(frame, confidence=1.0, predicted=False)

        self.kf.predict()
        if detection_uv is None:
            self.missed_frames += 1
            if self.missed_frames > self.max_occlusion_frames:
                return None
            return self._state(frame, confidence=0.0, predicted=True)

        self.kf.update(np.array([[detection_uv[0]], [detection_uv[1]]], dtype=float))
        self.missed_frames = 0
        return self._state(frame, confidence=1.0, predicted=False)

    def _state(self, frame: int, confidence: float, predicted: bool) -> dict[str, Any]:
        return {
            "frame": int(frame),
            "u": float(self.kf.x[0, 0]),
            "v": float(self.kf.x[1, 0]),
            "du": float(self.kf.x[2, 0]),
            "dv": float(self.kf.x[3, 0]),
            "confidence": float(confidence),
            "predicted": bool(predicted),
        }


def kalman_track_detections(
    detections: Iterable[dict[str, Any]],
    fps: float,
    max_occlusion_frames: int = 10,
) -> list[dict[str, Any]]:
    """Run Kalman tracking over sparse detections with frame numbers."""
    rows = sorted(detections, key=lambda item: int(item["frame"]))
    if not rows:
        return []

    by_frame = {int(item["frame"]): item for item in rows}
    first, last = int(rows[0]["frame"]), int(rows[-1]["frame"])
    tracker = BallTracker(fps=fps, max_occlusion_frames=max_occlusion_frames)
    tracked: list[dict[str, Any]] = []

    for frame in range(first, last + 1):
        item = by_frame.get(frame)
        detection = None if item is None else (float(item["x"]), float(item["y"]))
        state = tracker.update(detection, frame)
        if state is not None:
            if item is not None:
                state["confidence"] = float(item.get("confidence", 1.0))
            tracked.append(state)

    return tracked


def reconstruct_3d_path(
    tracked_points: Iterable[dict[str, Any]],
    calibrator: PitchCalibrator,
    fps: float,
    release_height_m: float = 2.05,
    bounce_height_m: float = 0.0,
    smooth_samples: int | None = None,
) -> dict[str, Any]:
    """Convert tracked pixels to a smooth renderer-ready metric path."""
    points = list(tracked_points)
    if len(points) < 4:
        return {"points": [], "method": "insufficient_points"}

    frames = np.asarray([int(p["frame"]) for p in points], dtype=float)
    uv = np.asarray([[float(p["u"]), float(p["v"])] for p in points], dtype=np.float32)
    xy = calibrator.image_to_world(uv)

    # Bounce is approximated as the lowest image-space ball point, which usually
    # corresponds to first ground contact from the umpire angle.
    v_values = uv[:, 1]
    bounce_idx = int(np.argmax(v_values))
    progress = (frames - frames[0]) / max(frames[-1] - frames[0], 1.0)
    bounce_progress = progress[bounce_idx]

    z = _estimate_monocular_height(progress, bounce_progress, release_height_m, bounce_height_m)

    if smooth_samples is None:
        smooth_samples = max(len(points), min(180, int((frames[-1] - frames[0]) + 1)))
    sample_frames = np.linspace(frames[0], frames[-1], int(smooth_samples), dtype=float)

    # Cubic splines smooth YOLO jitter while preserving the measured time axis.
    x_spline = CubicSpline(frames, xy[:, 0], bc_type="natural")
    y_spline = CubicSpline(frames, xy[:, 1], bc_type="natural")
    z_spline = CubicSpline(frames, z, bc_type="natural")
    smooth_xyz = np.column_stack([x_spline(sample_frames), y_spline(sample_frames), z_spline(sample_frames)])

    return {
        "points": [
            {
                "frame": int(round(frame)),
                "3d_pos": [round(float(pos[0]), 4), round(float(pos[1]), 4), round(float(pos[2]), 4)],
            }
            for frame, pos in zip(sample_frames, smooth_xyz)
        ],
        "bounce_frame": int(frames[bounce_idx]),
        "method": "homography_xy_plus_monocular_physics_z",
        "z_note": "X/Y are metric pitch-plane coordinates. Z is a monocular physics estimate.",
        "fps": round(float(fps), 3),
    }


def _estimate_monocular_height(
    progress: np.ndarray,
    bounce_progress: float,
    release_height_m: float,
    bounce_height_m: float,
) -> np.ndarray:
    before = progress <= bounce_progress
    z = np.zeros_like(progress, dtype=float)
    if np.any(before):
        t = progress[before] / max(bounce_progress, 1e-6)
        z[before] = release_height_m * (1.0 - t) ** 1.35 + bounce_height_m * t
    if np.any(~before):
        t = (progress[~before] - bounce_progress) / max(1.0 - bounce_progress, 1e-6)
        z[~before] = 0.55 * np.sin(np.pi * np.clip(t, 0.0, 1.0))
    return np.maximum(z, 0.0)


def calculate_ball_metrics(path_points: Iterable[dict[str, Any]], fps: float) -> dict[str, Any]:
    """Calculate release speed and swing from metric 3D coordinates."""
    rows = list(path_points)
    if len(rows) < 5 or fps <= 1:
        return {"release_speed_kmh": None, "swing_cm": 0.0, "is_swinging": False}

    frames = np.asarray([float(row["frame"]) for row in rows], dtype=float)
    xyz = np.asarray([row["3d_pos"] for row in rows], dtype=float)

    deltas = np.diff(xyz, axis=0)
    frame_gaps = np.maximum(np.diff(frames), 1.0)
    speeds_ms = np.linalg.norm(deltas, axis=1) * float(fps) / frame_gaps
    release_speed_kmh = float(np.median(speeds_ms[: min(5, len(speeds_ms))]) * 3.6)

    release = xyz[0, :2]
    pitch = xyz[min(len(xyz) - 1, int(np.argmax(xyz[:, 1]))), :2]
    line = pitch - release
    line_norm = float(np.linalg.norm(line))
    if line_norm <= 1e-9:
        swing_cm = 0.0
    else:
        vectors = xyz[:, :2] - release
        # 2D cross product magnitude / line length = perpendicular distance.
        lateral_m = np.abs(vectors[:, 0] * line[1] - vectors[:, 1] * line[0]) / line_norm
        swing_cm = float(np.max(lateral_m) * 100.0)

    velocities = np.concatenate([[0.0], speeds_ms]).astype(float)
    return {
        "release_speed_kmh": round(release_speed_kmh, 2),
        "swing_cm": round(swing_cm, 2),
        "is_swinging": bool(swing_cm >= 12.0),
        "velocity_kmh": np.round(velocities * 3.6, 3).tolist(),
    }


def export_renderer_json(path: dict[str, Any], metrics: dict[str, Any]) -> dict[str, Any]:
    """Renderer-friendly JSON payload for Flutter, Unity, or Three.js."""
    points = path.get("points", [])
    velocities = metrics.get("velocity_kmh", [])
    return {
        "format": "cricknova_3d_path_v1",
        "method": path.get("method"),
        "z_note": path.get("z_note"),
        "metrics": metrics,
        "points": [
            {
                "frame": int(point["frame"]),
                "3d_pos": point["3d_pos"],
                "velocity": float(velocities[index]) if index < len(velocities) else None,
                "is_swinging": bool(metrics.get("is_swinging", False)),
            }
            for index, point in enumerate(points)
        ],
    }


def build_volumetric_analysis(
    detections: Iterable[dict[str, Any]],
    calibration_points: Iterable[Iterable[float]],
    fps: float,
) -> dict[str, Any]:
    """Complete class-based pipeline from YOLO detections to 3D JSON."""
    calibrator = PitchCalibrator.from_points(calibration_points)
    tracked = kalman_track_detections(detections, fps=fps)
    path = reconstruct_3d_path(tracked, calibrator, fps=fps)
    metrics = calculate_ball_metrics(path.get("points", []), fps=fps)
    renderer_json = export_renderer_json(path, metrics)
    renderer_json["calibration"] = calibrator.to_json()
    renderer_json["tracked_point_count"] = len(tracked)
    return renderer_json


def dumps_renderer_json(payload: dict[str, Any]) -> str:
    return json.dumps(payload, separators=(",", ":"), ensure_ascii=True)
