# FILE: cricknova_engine/scripts/train_spin_model.py

from ultralytics import YOLO

def train_spin_detector():
    """
    Trains a YOLO model to detect seam orientation on cricket balls.
    """

    print("🔥 Training Spin/Seam Detector Started...")

    # Use nano model for faster experimentation or small dataset stability
    model = YOLO("yolov8n.pt")

    model.train(
        data="cricknova_engine/data/seam_dataset.yaml",
        epochs=80,
        imgsz=640,
        batch=16,
        name="seam_detector",
        patience=30,
        workers=4,
        cache=True,
        cos_lr=True,
        close_mosaic=10,
        lr0=0.002,
        augment=True
    )

    print("🎯 Spin / Seam model training complete!")

if __name__ == "__main__":
    train_spin_detector()