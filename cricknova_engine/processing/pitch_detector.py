import cv2
import numpy as np
from typing import List, Tuple, Optional

class PitchDetector:
    """
    Dynamic pitch detection for real speed calculation.
    Automatically detects pitch boundaries from cricket video frames.
    """

    def __init__(self):
        self.standard_pitch_length_m = 20.12  # 22 yards in meters
        self.standard_pitch_width_m = 3.05    # 10 feet in meters

    def detect_pitch_boundaries(self, frame: np.ndarray) -> Optional[List[Tuple[float, float]]]:
        """
        Detect pitch boundaries using edge detection and line analysis.
        Returns 4 corner points: [top-left, top-right, bottom-right, bottom-left]
        in pixel coordinates, or None if detection fails.
        """
        try:
            # Convert to grayscale
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

            # Apply Gaussian blur to reduce noise
            blurred = cv2.GaussianBlur(gray, (5, 5), 0)

            # Edge detection using Canny
            edges = cv2.Canny(blurred, 50, 150)

            # Dilate edges to connect broken lines
            kernel = np.ones((3, 3), np.uint8)
            dilated = cv2.dilate(edges, kernel, iterations=1)

            # Find lines using Hough transform
            lines = cv2.HoughLinesP(dilated, 1, np.pi/180, threshold=100,
                                  minLineLength=100, maxLineGap=50)

            if lines is None:
                return None

            # Extract line segments
            line_segments = []
            for line in lines:
                x1, y1, x2, y2 = line[0]
                line_segments.append(((x1, y1), (x2, y2)))

            # Find pitch rectangle using geometric analysis
            pitch_corners = self._find_pitch_rectangle(line_segments, frame.shape)

            return pitch_corners

        except Exception as e:
            print(f"Pitch detection failed: {e}")
            return None

    def _find_pitch_rectangle(self, lines: List[Tuple], frame_shape: Tuple) -> Optional[List[Tuple[float, float]]]:
        """
        Analyze detected lines to find the pitch rectangle.
        Uses heuristics for cricket pitch geometry.
        """
        height, width = frame_shape[:2]

        # Find horizontal and vertical lines
        horizontal_lines = []
        vertical_lines = []

        for (p1, p2) in lines:
            x1, y1 = p1
            x2, y2 = p2

            # Calculate line angle
            if x2 - x1 != 0:
                angle = abs(np.arctan((y2 - y1) / (x2 - x1)) * 180 / np.pi)
            else:
                angle = 90

            # Classify as horizontal or vertical
            if angle < 10:  # Nearly horizontal
                horizontal_lines.append((p1, p2))
            elif angle > 80:  # Nearly vertical
                vertical_lines.append((p1, p2))

        if len(horizontal_lines) < 2 or len(vertical_lines) < 2:
            return None

        # Find the most likely pitch boundaries
        # Look for lines that form a rectangle in the expected pitch area
        pitch_bounds = self._extract_pitch_bounds(horizontal_lines, vertical_lines, width, height)

        return pitch_bounds

    def _extract_pitch_bounds(self, h_lines: List, v_lines: List, width: int, height: int) -> Optional[List[Tuple[float, float]]]:
        """
        Extract the 4 corner points of the pitch from detected lines.
        """
        # Get all y-coordinates from horizontal lines (potential pitch edges)
        y_coords = []
        for (p1, p2) in h_lines:
            y_coords.extend([p1[1], p2[1]])

        # Get all x-coordinates from vertical lines (potential pitch sides)
        x_coords = []
        for (p1, p2) in v_lines:
            x_coords.extend([p1[0], p2[0]])

        if not y_coords or not x_coords:
            return None

        # Sort coordinates
        y_coords.sort()
        x_coords.sort()

        # Use the middle range of coordinates (most likely to be pitch)
        y_mid_start = int(len(y_coords) * 0.3)
        y_mid_end = int(len(y_coords) * 0.7)
        x_mid_start = int(len(x_coords) * 0.2)
        x_mid_end = int(len(x_coords) * 0.8)

        pitch_ys = y_coords[y_mid_start:y_mid_end]
        pitch_xs = x_coords[x_mid_start:x_mid_end]

        if len(pitch_ys) < 2 or len(pitch_xs) < 2:
            return None

        # Define pitch corners
        # Assuming camera perspective: top is bowler end (further), bottom is batsman end (closer)
        top_y = min(pitch_ys)
        bottom_y = max(pitch_ys)
        left_x = min(pitch_xs)
        right_x = max(pitch_xs)

        # In perspective, the far end (top) appears narrower
        # Adjust for perspective distortion
        top_width_factor = 0.7  # Far end appears ~70% as wide
        top_left_x = left_x + (right_x - left_x) * (1 - top_width_factor) / 2
        top_right_x = right_x - (right_x - left_x) * (1 - top_width_factor) / 2

        corners = [
            (top_left_x, top_y),      # Top-left (bowler end)
            (top_right_x, top_y),     # Top-right (bowler end)
            (right_x, bottom_y),      # Bottom-right (batsman end)
            (left_x, bottom_y)        # Bottom-left (batsman end)
        ]

        return corners

    def get_homography_matrix(self, pitch_corners: List[Tuple[float, float]]) -> Optional[np.ndarray]:
        """
        Calculate homography matrix to transform pixel coordinates to real-world meters.
        """
        if not pitch_corners or len(pitch_corners) != 4:
            return None

        # Source points (detected pitch corners in pixel coordinates)
        src_pts = np.float32(pitch_corners)

        # Destination points (real pitch dimensions in meters)
        dst_pts = np.float32([
            [0, 0],                              # Top-left
            [self.standard_pitch_width_m, 0],     # Top-right
            [self.standard_pitch_width_m, self.standard_pitch_length_m],  # Bottom-right
            [0, self.standard_pitch_length_m]     # Bottom-left
        ])

        try:
            # Calculate homography matrix
            matrix, _ = cv2.findHomography(src_pts, dst_pts)
            return matrix
        except Exception as e:
            print(f"Homography calculation failed: {e}")
            return None

    def validate_pitch_detection(self, corners: List[Tuple[float, float]], frame_shape: Tuple) -> bool:
        """
        Validate that detected corners form a reasonable pitch rectangle.
        """
        if not corners or len(corners) != 4:
            return False

        height, width = frame_shape[:2]

        # Check that corners are within frame bounds
        for x, y in corners:
            if x < 0 or x >= width or y < 0 or y >= height:
                return False

        # Check aspect ratio is reasonable for a cricket pitch
        # Pitch is 20.12m x 3.05m, so aspect ratio should be ~6.6:1
        xs = [p[0] for p in corners]
        ys = [p[1] for p in corners]

        pitch_width_px = max(xs) - min(xs)
        pitch_height_px = max(ys) - min(ys)

        if pitch_width_px == 0 or pitch_height_px == 0:
            return False

        aspect_ratio = pitch_height_px / pitch_width_px

        # Allow some tolerance (pitch should appear taller than wide in most camera angles)
        # Relaxed constraints for various camera angles
        if aspect_ratio < 0.3 or aspect_ratio > 20:
            return False

        return True
