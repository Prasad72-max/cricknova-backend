import math

# Real pitch distance in meters for speed approximation
PIXEL_TO_METER = 0.02   # adjustable scaling

def compute_speed(track):
    """Compute ball speed from pixel movement"""
    if len(track) < 2:
        return 0

    x1, y1 = track[0]
    x2, y2 = track[-1]

    dist_pixels = math.dist((x1, y1), (x2, y2))
    dist_m = dist_pixels * PIXEL_TO_METER

    # assume video = 30 fps
    time_s = len(track) / 30

    speed_m_s = dist_m / time_s
    speed_kmh = speed_m_s * 3.6

    return speed_kmh

def compute_swing(track):
    """Compute horizontal swing angle"""
    if len(track) < 2:
        return 0

    x1, y1 = track[0]
    x2, y2 = track[-1]

    dx = x2 - x1
    dy = y1 - y2

    angle = math.degrees(math.atan2(dx, dy))
    return angle