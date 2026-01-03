from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI
import os

router = APIRouter()

# -----------------------------
# OPENAI CLIENT (SAFE)
# -----------------------------
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

if not OPENAI_API_KEY:
    raise RuntimeError("OPENAI_API_KEY environment variable is not set")

client = OpenAI(api_key=OPENAI_API_KEY)

# -----------------------------
# REQUEST MODEL
# -----------------------------
class CoachRequest(BaseModel):
    message: str | None = None
    role: str = "batsman"

# -----------------------------
# AI COACH ENDPOINT
# -----------------------------
@router.post("/coach/chat")
async def ai_coach(req: CoachRequest):
    if not req.message or not req.message.strip():
        return {
            "reply": "Please ask a cricket-related question."
        }
    try:
        prompt = f"""
You are an elite cricket AI coach.
User role: {req.role}

Give practical, short, technical advice.
No motivation talk. Only technique and drills.

Question:
{req.message}
"""

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "user", "content": prompt}
            ],
            temperature=0.4,
            max_tokens=180
        )

        return {
            "reply": response.choices[0].message.content.strip()
        }

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"AI Coach error: {str(e)}"
        )