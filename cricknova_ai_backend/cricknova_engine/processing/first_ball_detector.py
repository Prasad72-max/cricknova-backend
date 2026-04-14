"""
FIRST BALL DETECTOR
Detects and analyzes ONLY the first ball delivered in a training video.
Tracks: Release, Bounce, Post-bounce movement
"""

import numpy as np
import cv2
from ultralytics import YOLO


class FirstBallDetector:
    def __init__(self, model_path="yolo11n.pt"):
        """Initialize YOLO model for ball detection"""
        try:
            self.model = YOLO(model_path)
        except:
            self.model = None
            print(f"⚠️  Could not load YOLO model from {model_path}")
    
    def detect_first_ball(self, video_path):
        """
        Detects and tracks ONLY the first ball in the video.
        
        Returns:
            dict with:
                - release_frame: Frame number where ball is released
                - release_point: (x, y) coordinates of release
                - bounce_frame: Frame number where ball bounces
                - bounce_point: (x, y) coordinates of bounce
                - trajectory: List of (x, y) ball positions for first delivery
                - post_bounce_trajectory: Ball path after bounce
                - status: "success" or "error"
        """
        if self.model is None:
            return {"status": "error", "message": "YOLO model not loaded"}
        
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            return {"status": "error", "message": "Could not open video"}
        
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        
        ball_detections = []  # (frame_idx, x, y, confidence)
        frame_idx = 0
        
        print("🔍 Scanning video for first ball...")
        
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            
            # Run YOLO detection
            results = self.model(frame, verbose=False, device="cpu")
            
            # Find the ball (class 32 is sports ball in COCO, or 0 if custom trained)
            for r in results:
                boxes = r.boxes
                for box in boxes:
                    cls = int(box.cls[0])
                    conf = float(box.conf[0])
                    
                    # Accept if confidence > 0.3
                    if conf > 0.3:
                        # Get center of bounding box
                        x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
                        cx = (x1 + x2) / 2
                        cy = (y1 + y2) / 2
                        
                        ball_detections.append((frame_idx, cx, cy, conf))
            
            frame_idx += 1
        
        cap.release()
        
        if len(ball_detections) < 5:
            return {
                "status": "error", 
                "message": "Not enough ball detections found"
            }
        
        # Analyze detections to find first ball delivery
        result = self._analyze_first_ball(ball_detections, frame_width, frame_height)
        result["fps"] = fps
        result["video_resolution"] = (frame_width, frame_height)
        
        return result
    
    def _analyze_first_ball(self, detections, width, height):
        """
        Analyzes ball detections to identify:
        - Release point (first appearance)
        - Bounce point (sudden Y direction change)
        - Post-bounce trajectory
        """
        if len(detections) < 5:
            return {"status": "error", "message": "Insufficient detections"}
        
        # Group consecutive detections (first ball = first continuous sequence)
        first_ball_detections = self._extract_first_delivery(detections)
        
        if len(first_ball_detections) < 5:
            return {"status": "error", "message": "First ball too short"}
        
        # Identify release point (first detection)
        release_frame, release_x, release_y, _ = first_ball_detections[0]
        
        # Identify bounce point (sudden Y velocity change)
        bounce_data = self._detect_bounce(first_ball_detections)
        
        # Normalize coordinates to 0-1 range for frontend
        trajectory_normalized = [
            {
                "x": x / width,
                "y": y / height,
                "frame": frame
            }
            for frame, x, y, _ in first_ball_detections
        ]
        
        result = {
            "status": "success",
            "release_frame": int(release_frame),
            "release_point": {
                "x": float(release_x / width),
                "y": float(release_y / height)
            },
            "trajectory": trajectory_normalized,
            "total_detections": len(first_ball_detections)
        }
        
        # Add bounce information if detected
        if bounce_data:
            result["bounce_frame"] = bounce_data["frame"]
            result["bounce_point"] = {
                "x": float(bounce_data["x"] / width),
                "y": float(bounce_data["y"] / height)
            }
            result["post_bounce_trajectory"] = [
                {
                    "x": p["x"] / width,
                    "y": p["y"] / height,
                    "frame": p["frame"]
                }
                for p in bounce_data["post_bounce"]
            ]
        
        return result
    
    def _extract_first_delivery(self, detections):
        """
        Extracts first continuous ball delivery from all detections.
        A delivery ends when there's a gap of >10 frames or ball exits frame.
        """
        if not detections:
            return []
        
        first_delivery = [detections[0]]
        
        for i in range(1, len(detections)):
            prev_frame = detections[i-1][0]
            curr_frame = detections[i][0]
            
            # If gap is too large, assume first ball ended
            if curr_frame - prev_frame > 10:
                break
            
            first_delivery.append(detections[i])
            
            # Stop after reasonable number of frames (first ball delivered)
            if len(first_delivery) >= 50:  # ~1.5 seconds at 30fps
                break
        
        return first_delivery
    
    def _detect_bounce(self, detections):
        """
        Detects bounce point by analyzing Y velocity changes.
        Bounce = downward motion suddenly reverses or slows significantly.
        """
        if len(detections) < 5:
            return None
        
        # Calculate Y velocities
        velocities = []
        for i in range(1, len(detections)):
            frame_prev, x_prev, y_prev, _ = detections[i-1]
            frame_curr, x_curr, y_curr, _ = detections[i]
            
            dy = y_curr - y_prev
            dt = frame_curr - frame_prev
            
            if dt > 0:
                vy = dy / dt
                velocities.append((i, vy, y_curr))
        
        # Find bounce: Y velocity changes from positive to negative
        # (positive Y = downward in image coordinates)
        bounce_idx = None
        for i in range(1, len(velocities)):
            prev_vy = velocities[i-1][1]
            curr_vy = velocities[i][1]
            
            # Bounce detected: motion reversal or significant slowdown
            if prev_vy > 5 and curr_vy < -2:
                bounce_idx = velocities[i][0]
                break
            elif prev_vy > 10 and abs(curr_vy) < 2:
                bounce_idx = velocities[i][0]
                break
        
        if bounce_idx is None or bounce_idx >= len(detections) - 2:
            return None
        
        bounce_frame, bounce_x, bounce_y, _ = detections[bounce_idx]
        
        # Post-bounce trajectory
        post_bounce = []
        for i in range(bounce_idx + 1, len(detections)):
            frame, x, y, _ = detections[i]
            post_bounce.append({
                "frame": int(frame),
                "x": float(x),
                "y": float(y)
            })
        
        return {
            "frame": int(bounce_frame),
            "x": float(bounce_x),
            "y": float(bounce_y),
            "post_bounce": post_bounce
        }


# Helper function for API usage
def analyze_first_ball(video_path, model_path="yolo11n.pt"):
    """
    Convenience function to analyze first ball in video.
    
    Args:
        video_path: Path to video file
        model_path: Path to YOLO model weights
        
    Returns:
        Analysis results dictionary
    """
    detector = FirstBallDetector(model_path)
    return detector.detect_first_ball(video_path)
