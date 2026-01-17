# FILE: cricknova_engine/scripts/train_spin_model.py

from ultralytics import YOLO

def train_spin_detector():
    """
    Trains a YOLO model to detect seam orientation on cricket balls.
    """

    print("🔥 Training Spin/Seam Detector Started...")

    # Using YOLOv8s for better small-object detection
    model = YOLO("yolov8s.pt")

    model.train(
        data="cricknova_engine/data/seam_dataset.yaml",
        epochs=60,
        imgsz=640,
        batch=12,
        name="seam_detector",
        patience=25,
        workers=4,
        augment=True
    )

    print("🎯 Spin / Seam model training complete!")

if __name__ == "__main__":
    train_spin_detector()