#!/usr/bin/env python3
"""
Test script for real speed calculation with dynamic pitch detection.
"""

import cv2
import numpy as np
from cricknova_engine.processing.pitch_detector import PitchDetector
from cricknova_engine.processing.speed import calculate_speed
from cricknova_engine.processing.ball_tracker_motion import track_ball_positions

def test_pitch_detection(video_path):
    """Test pitch detection on a video."""
    print(f"Testing pitch detection on: {video_path}")

    # Read first frame
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print("Could not open video")
        return

    ret, frame = cap.read()
    cap.release()

    if not ret:
        print("Could not read frame")
        return

    # Test pitch detection
    detector = PitchDetector()
    corners = detector.detect_pitch_boundaries(frame)

    if corners:
        print(f"Detected pitch corners: {corners}")
        is_valid = detector.validate_pitch_detection(corners, frame.shape)
        print(f"Pitch detection validation: {is_valid}")

        if is_valid:
            matrix = detector.get_homography_matrix(corners)
            print("Homography matrix calculated successfully")
            return matrix
    else:
        print("Pitch detection failed")

    return None

def test_speed_calculation(video_path):
    """Test complete speed calculation pipeline."""
    print(f"\nTesting speed calculation on: {video_path}")

    # Track ball
    positions = track_ball_positions(video_path, max_frames=60)
    print(f"Tracked {len(positions)} ball positions")

    if len(positions) < 5:
        print("Not enough positions for speed calculation")
        return

    # Get reference frame
    cap = cv2.VideoCapture(video_path)
    ret, reference_frame = cap.read()
    cap.release()

    if not ret:
        print("Could not get reference frame")
        return

    # Calculate speed with dynamic pitch detection
    speed = calculate_speed(positions, fps=30, reference_frame=reference_frame)
    print(f"Calculated speed: {speed} km/h")

    return speed

if __name__ == "__main__":
    # Test with first available video
    import os
    import glob

    video_files = glob.glob("temp_*.mp4")
    if video_files:
        video_path = video_files[0]
        print(f"Using test video: {video_path}")

        # Test pitch detection
        matrix = test_pitch_detection(video_path)

        # Test full speed calculation
        speed = test_speed_calculation(video_path)

        print("\nTest completed!")
        if speed and speed > 0:
            print("✓ Real speed calculation working!")
        else:
            print("⚠ Speed calculation returned 0 - may need adjustment")
    else:
        print("No test videos found (temp_*.mp4)")
