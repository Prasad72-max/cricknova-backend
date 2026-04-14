

from ultralytics import YOLO

if __name__ == "__main__":
    # Lightweight model for small-object ball tracking stability
    model = YOLO("yolov8n.pt")

    model.train(
        data="cricknova_engine/data/swing_dataset.yaml",
        epochs=80,
        imgsz=640,
        batch=16,
        name="swing_detector",
        patience=30,
        workers=4,
        cache=True,
        cos_lr=True,
        close_mosaic=10,
        lr0=0.002,
        augment=True
    )