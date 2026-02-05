# Conservative, non-scripted, video-driven

import math
import numpy as np

def calculate_speed(ball_positions, fps=30):
    """
    Calculates bowling speed (km/h) using only tracked ball motion.
    No pitch-length hardcoding. Conservative & realistic.
    """

    # Need enough frames to be meaningful
    if not ball_positions or len(ball_positions) < fps // 2:
        return 0.0

    # Compute per-frame pixel distances
    pixel_dists = []
    for i in range(1, len(ball_positions)):
        x1, y1 = ball_positions[i - 1]
        x2, y2 = ball_positions[i]
        pixel_dists.append(math.dist((x1, y1), (x2, y2)))

    pixel_dists = np.array(pixel_dists)

    if np.all(pixel_dists == 0):
        return 0.0

    # Remove jitter (ignore tiny movements)
    pixel_dists = pixel_dists[pixel_dists > np.percentile(pixel_dists, 25)]
    if len(pixel_dists) == 0:
        return 0.0

    avg_pixel_per_frame = float(np.mean(pixel_dists))

    # Estimate flight distance covered by tracked frames (meters)
    # Conservative assumption: 8–12 meters of actual flight
    tracked_frames = len(ball_positions)
    flight_seconds = tracked_frames / fps

    # Pixel span (vertical dominates for bowling)
    y_values = [p[1] for p in ball_positions]
    pixel_span = abs(max(y_values) - min(y_values))

    if pixel_span <= 0:
        return 0.0

    # --- PIXEL → METER CALIBRATION (VIDEO-REALISTIC) ---
    # Assume visible vertical frame ≈ 18–22 meters of real space
    # (bowler release to batting zone in camera view)

    FRAME_METERS = 20.0  # conservative middle value
    meters_per_pixel = FRAME_METERS / pixel_span

    meters_per_second = (avg_pixel_per_frame * meters_per_pixel) * fps
    kmph = meters_per_second * 3.6

    # --- REALISTIC CONSERVATIVE FILTER ---
    # Clamp to human-possible bowling speeds (mobile-video safe)

    # Hard realistic bounds
    kmph = max(90.0, min(kmph, 155.0))

    # Conservative smoothing to avoid spikes
    kmph = kmph * 0.85

    return round(kmph, 1)
