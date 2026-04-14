import cv2
import os

def split_deliveries(video_path, output_folder, min_movement=15, idle_frames=25):
    """
    Automatically splits a cricket net session video into separate deliveries.
    
    Args:
        video_path (str): Path to input video.
        output_folder (str): Folder to save individual deliveries.
        min_movement (int): Pixel movement threshold to detect ball.
        idle_frames (int): Number of frames with no motion = delivery ended.
    """

    if not os.path.exists(output_folder):
        os.makedirs(output_folder)

    cap = cv2.VideoCapture(video_path)
    frame_id = 0
    delivery_id = 1

    ret, prev_frame = cap.read()
    if not ret:
        print("Error: Cannot read video.")
        return

    prev_gray = cv2.cvtColor(prev_frame, cv2.COLOR_BGR2GRAY)
    consecutive_idle = 0
    recording = False
    out = None

    fourcc = cv2.VideoWriter_fourcc(*'mp4v')

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        # Difference between frames
        diff = cv2.absdiff(prev_gray, gray)
        movement = cv2.countNonZero(cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)[1])

        # Ball (movement) detected
        if movement > min_movement:
            consecutive_idle = 0

            if not recording:
                # Start new delivery recording
                delivery_path = os.path.join(
                    output_folder, f"delivery_{delivery_id}.mp4"
                )
                out = cv2.VideoWriter(delivery_path, fourcc, 30,
                                      (frame.shape[1], frame.shape[0]))
                print(f"Recording Delivery {delivery_id}...")
                recording = True

            out.write(frame)

        else:
            # No movement
            consecutive_idle += 1

            # Delivery ends when idle for many frames
            if recording and consecutive_idle > idle_frames:
                recording = False
                out.release()
                print(f"Delivery {delivery_id} saved.")
                delivery_id += 1

        prev_gray = gray
        frame_id += 1

    # Clean up
    cap.release()
    if out:
        out.release()

    print("Splitting complete!")
