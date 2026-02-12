from fastapi import FastAPI, UploadFile, File
import tempfile
import shutil
import os
from .first_ball_detector import analyze_first_ball

app = FastAPI()


@app.post("/training/analyze")
async def analyze_video(file: UploadFile = File(...)):
    """
    Analyzes ONLY the first ball delivered in a training video.
    
    Detection pipeline:
    1. Detect all balls in video
    2. Extract ONLY first ball trajectory
    3. Identify: Release, Bounce, Post-bounce movement
    4. Calculate speed, swing, spin
    """
    
    # Save uploaded video to temporary file
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
        shutil.copyfileobj(file.file, tmp)
        video_path = tmp.name
    
    try:
        # Detect first ball using YOLO
        model_path = "yolo11n.pt"
        if os.path.exists("cricknova_engine/detectors/model.pt"):
            model_path = "cricknova_engine/detectors/model.pt"
        
        result = analyze_first_ball(video_path, model_path)
        
        if result.get("status") == "error":
            return {
                "status": "error",
                "message": result.get("message", "Could not detect ball"),
                "speed_kmph": None,
                "swing": None,
                "spin": None,
                "trajectory": []
            }
        
        # Calculate speed from trajectory
        speed_kmph = calculate_speed(result)
        
        # Analyze swing from trajectory
        swing = analyze_swing(result)
        
        # Analyze spin from post-bounce trajectory
        spin = analyze_spin(result)
        
        return {
            "status": "success",
            "speed_kmph": speed_kmph,
            "swing": swing,
            "spin": spin,
            "release_point": result.get("release_point"),
            "bounce_point": result.get("bounce_point"),
            "trajectory": result.get("trajectory", []),
            "post_bounce_trajectory": result.get("post_bounce_trajectory", []),
            "release_frame": result.get("release_frame"),
            "bounce_frame": result.get("bounce_frame"),
            "fps": result.get("fps"),
        }
    
    finally:
        # Clean up temporary file
        if os.path.exists(video_path):
            os.remove(video_path)


def calculate_speed(ball_data):
    """
    Calculate ball speed from trajectory data.
    Uses distance and time between release and bounce.
    """
    trajectory = ball_data.get("trajectory", [])
    fps = ball_data.get("fps", 30)
    
    if len(trajectory) < 2:
        return 120.0  # Default
    
    # Get first and last points
    start = trajectory[0]
    end = trajectory[-1]
    
    # Calculate distance (normalized coordinates)
    dx = end["x"] - start["x"]
    dy = end["y"] - start["y"]
    distance_normalized = (dx**2 + dy**2) ** 0.5
    
    # Time in seconds
    frame_diff = end["frame"] - start["frame"]
    time_seconds = frame_diff / fps
    
    if time_seconds == 0:
        return 120.0
    
    # Estimate speed (assuming pitch is ~20m, camera captures ~0.6 of frame width)
    # This is a rough approximation
    pitch_length = 20  # meters
    distance_meters = distance_normalized * pitch_length
    speed_ms = distance_meters / time_seconds
    speed_kmph = speed_ms * 3.6
    
    # Clamp to realistic bowling speeds (80-165 km/h)
    speed_kmph = max(80, min(165, speed_kmph))
    
    return round(speed_kmph, 1)


def analyze_swing(ball_data):
    """
    Analyze swing from trajectory.
    Checks horizontal deviation during flight.
    """
    trajectory = ball_data.get("trajectory", [])
    
    if len(trajectory) < 5:
        return "Straight"
    
    # Get horizontal positions
    x_positions = [p["x"] for p in trajectory]
    
    # Calculate horizontal movement
    start_x = x_positions[0]
    mid_x = x_positions[len(x_positions) // 2]
    end_x = x_positions[-1]
    
    # Check deviation from straight line
    expected_mid_x = (start_x + end_x) / 2
    deviation = mid_x - expected_mid_x
    
    # Threshold for swing detection (5% of frame width)
    swing_threshold = 0.05
    
    if deviation > swing_threshold:
        return "Outswing"
    elif deviation < -swing_threshold:
        return "Inswing"
    else:
        return "Straight"


def analyze_spin(ball_data):
    """
    Analyze spin using post-bounce trajectory.
    Measures horizontal deviation after bounce.
    """
    post_bounce = ball_data.get("post_bounce_trajectory", [])

    if len(post_bounce) < 4:
        return "Straight"

    x_positions = [p["x"] for p in post_bounce]

    start_x = x_positions[0]
    end_x = x_positions[-1]

    deviation = end_x - start_x

    spin_threshold = 0.03  # smaller threshold after bounce

    if deviation > spin_threshold:
        return "Leg Spin"
    elif deviation < -spin_threshold:
        return "Off Spin"
    else:
        return "Straight"
