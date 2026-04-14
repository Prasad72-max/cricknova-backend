# FILE: cricknova_engine/scripts/train_ball_detector.py

from ultralytics import YOLO

def train_ball_detector():
    """
    Trains a YOLO model to detect cricket ball.
    """

    print("🔥 Training Cricket Ball Detector Started...")

    # Load YOLOv8 or YOLOv11 (auto-detect)
    model = YOLO("yolov8n.pt")   # lightweight, good for mobile

    # Train the model
    model.train(
        data="cricknova_engine/data/ball_dataset.yaml",   # dataset path
        epochs=50,
        imgsz=640,
        batch=16,
        name="ball_detector",
        patience=20,
        augment=True
    )

    print("🎯 Training Complete! Model saved in runs/detect/ball_detector")

if __name__ == "__main__":
    train_ball_detector()