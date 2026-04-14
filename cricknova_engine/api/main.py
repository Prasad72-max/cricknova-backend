import os
import httpx
from pydantic import BaseModel
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from cricknova_engine.utils.frame_extractor import extract_frames
from cricknova_engine.utils.ball_tracker import track_ball
from cricknova_engine.utils.metrics import compute_speed, compute_swing
import shutil
import uuid

app = FastAPI()

# Allow Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = "uploaded_videos"
os.makedirs(UPLOAD_DIR, exist_ok=True)

# Cashfree config variables
CASHFREE_APP_ID = os.getenv("CASHFREE_APP_ID")
CASHFREE_SECRET_KEY = os.getenv("CASHFREE_SECRET_KEY")
CASHFREE_BASE_URL = "https://sandbox.cashfree.com/pg"  # change to prod later

@app.get("/")
def root():
    return {"status": "backend alive"}


# Pydantic models
class CreateOrderRequest(BaseModel):
    order_amount: float
    order_id: str
    customer_id: str
    customer_phone: str
    customer_email: str


# Cashfree create order endpoint
@app.post("/payment/create-order")
async def create_cashfree_order(data: CreateOrderRequest):
    headers = {
        "x-client-id": CASHFREE_APP_ID,
        "x-client-secret": CASHFREE_SECRET_KEY,
        "x-api-version": "2022-09-01",
        "Content-Type": "application/json",
    }

    payload = {
        "order_id": data.order_id,
        "order_amount": data.order_amount,
        "order_currency": "INR",
        "customer_details": {
            "customer_id": data.customer_id,
            "customer_phone": data.customer_phone,
            "customer_email": data.customer_email,
        }
    }

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{CASHFREE_BASE_URL}/orders",
            json=payload,
            headers=headers
        )

    if resp.status_code != 200:
        return {"status": "failed", "error": resp.text}

    return resp.json()

@app.post("/analyze")
async def analyze_video(file: UploadFile = File(...)):
    try:
        # Save uploaded file
        file_id = str(uuid.uuid4())
        save_path = f"{UPLOAD_DIR}/{file_id}.mp4"

        with open(save_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # Extract frames
        frames = extract_frames(save_path)

        if len(frames) < 5:
            return {"error": "Not enough frames to analyze"}

        # Track ball
        track = track_ball(frames)

        if len(track) < 2:
            return {"error": "Ball not detected"}

        # Compute metrics
        speed = compute_speed(track)
        swing = compute_swing(track)

        return {
            "ball_speed": round(speed, 2),
            "swing_angle": round(swing, 2),
            "spin_strength": 0,  # placeholder
            "frames_tracked": len(track),
        }

    except Exception as e:
        return {"error": str(e)}