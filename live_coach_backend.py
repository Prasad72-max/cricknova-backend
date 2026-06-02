import asyncio
import base64
import json
import os
import time
from contextlib import suppress
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from google.cloud import firestore
from google.genai import Client
from google.genai import types


app = FastAPI(title="CrickNova Live Nets Backend")

MODEL_NAME = "gemini-live-2.5-flash-native-audio"
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY") or os.getenv("GEMINI_API_KEY")

SYSTEM_INSTRUCTION = """Context & Role:
You are "CrickNova AI", an elite, high-energy, and sharp human cricket coach standing at the non-striker's end. You are talking directly into the batsman's earbuds in real-time via a live audio stream. You see their batting frames and hear the ball impact instantly. Your voice responses must be natural, fast, and sound exactly like a real human coach giving quick advice between deliveries.

The "No-Excuse Engine" Audio Protocol:
For every delivery where the batsman makes a mistake, speak a single, fluid paragraph. Immediately point out the main technical fault, the secondary balance error, the match impact, and the instant fix. You must keep your response under 25 words so the batsman can listen and react before the next ball is bowled.

Strict Audio Delivery Rules:
1. NEVER output text formatting like bullet points, asterisks, dashes, or structured headings.
2. Speak in short, punchy, conversational sentences. Use everyday cricket coaching language.
3. Keep it tightly focused. Do not waste words on generic filler phrases.
4. If the shot is brilliant, do not use the protocol. Just give an instant confidence boost like a proud coach.
"""

_firestore_client: firestore.Client | None = None
_gemini_client: Client | None = None


def db() -> firestore.Client:
    global _firestore_client
    if _firestore_client is None:
        _firestore_client = firestore.Client()
    return _firestore_client


def gemini() -> Client:
    global _gemini_client
    if _gemini_client is None:
        if not GOOGLE_API_KEY:
            raise RuntimeError("GOOGLE_API_KEY or GEMINI_API_KEY is required")
        _gemini_client = Client(api_key=GOOGLE_API_KEY)
    return _gemini_client


def _live_doc(user_id: str):
    return db().collection("users").document(user_id)


def _balance_ms_from_data(data: dict[str, Any]) -> int:
    if "live_milliseconds_remaining" in data:
        try:
            return max(0, int(data.get("live_milliseconds_remaining", 0)))
        except (TypeError, ValueError):
            return 0
    try:
        return max(0, int(data.get("live_seconds_remaining", 0)) * 1000)
    except (TypeError, ValueError):
        return 0


def _legacy_seconds(milliseconds: int) -> int:
    if milliseconds <= 0:
        return 0
    return (milliseconds + 999) // 1000


async def _get_balance_ms(user_id: str) -> int:
    def read() -> int:
        snap = _live_doc(user_id).get()
        return _balance_ms_from_data(snap.to_dict() if snap.exists else {})

    return await asyncio.to_thread(read)


async def _charge_elapsed_ms(user_id: str, elapsed_ms: int) -> int:
    @firestore.transactional
    def txn_body(transaction: firestore.Transaction) -> int:
        ref = _live_doc(user_id)
        snap = ref.get(transaction=transaction)
        current_ms = _balance_ms_from_data(snap.to_dict() if snap.exists else {})
        billed_ms = max(0, elapsed_ms)
        next_ms = max(0, current_ms - billed_ms)
        transaction.set(
            ref,
            {
                "live_milliseconds_remaining": next_ms,
                "live_seconds_remaining": _legacy_seconds(next_ms),
                "last_live_session_billed_ms": billed_ms,
                "last_live_session_ended_at": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        return next_ms

    def run() -> int:
        return txn_body(db().transaction())

    return await asyncio.to_thread(run)


async def _billing_guard(
    client_ws: WebSocket,
    stop: asyncio.Event,
    start_ns: int,
    starting_balance_ms: int,
) -> None:
    while not stop.is_set():
        await asyncio.sleep(0.1)
        elapsed_ms = (time.monotonic_ns() - start_ns) // 1_000_000
        remaining_ms = max(0, starting_balance_ms - elapsed_ms)
        await client_ws.send_json(
            {
                "type": "billing",
                "live_milliseconds_remaining": remaining_ms,
                "live_seconds_remaining": _legacy_seconds(remaining_ms),
                "elapsed_milliseconds": elapsed_ms,
            }
        )
        if remaining_ms <= 0:
            await client_ws.send_json(
                {"type": "termination", "reason": "LIVE_BALANCE_EXHAUSTED"}
            )
            stop.set()
            await client_ws.close(code=4001)
            return


async def _from_flutter(client_ws: WebSocket, live_session: Any, stop: asyncio.Event) -> None:
    while not stop.is_set():
        message = await client_ws.receive()
        raw = message.get("bytes")
        text = message.get("text")

        if text is not None:
            payload = json.loads(text)
            kind = payload.get("type")
            if kind == "video":
                frame = base64.b64decode(payload["data"])
                await live_session.send(input={"data": frame, "mime_type": "image/jpeg"})
            elif kind == "audio":
                audio = base64.b64decode(payload["data"])
                await live_session.send(input={"data": audio, "mime_type": "audio/pcm"})
            elif kind == "user_text":
                spoken = str(payload.get("text", "")).strip()
                if spoken:
                    await live_session.send(input=spoken, end_of_turn=True)
            elif kind == "stop":
                stop.set()
                return
            continue

        if raw:
            await live_session.send(input={"data": raw, "mime_type": "image/jpeg"})


async def _from_gemini(client_ws: WebSocket, live_session: Any, stop: asyncio.Event) -> None:
    async for response in live_session.receive():
        if stop.is_set():
            return
        server_content = getattr(response, "server_content", None)
        if server_content and getattr(server_content, "model_turn", None):
            for part in server_content.model_turn.parts:
                inline_data = getattr(part, "inline_data", None)
                if inline_data and inline_data.data:
                    await client_ws.send_bytes(inline_data.data)
                part_text = getattr(part, "text", None)
                if part_text:
                    await client_ws.send_json({"type": "transcript", "text": part_text})
        text = getattr(response, "text", None)
        if text:
            await client_ws.send_json({"type": "transcript", "text": text})


@app.websocket("/ws/live-nets/{user_id}")
async def live_nets_socket(websocket: WebSocket, user_id: str) -> None:
    await websocket.accept()
    starting_balance_ms = await _get_balance_ms(user_id)
    if starting_balance_ms <= 0:
        await websocket.send_json({"type": "termination", "reason": "NO_LIVE_BALANCE"})
        await websocket.close(code=4003)
        return

    await websocket.send_json(
        {
            "type": "ready",
            "live_milliseconds_remaining": starting_balance_ms,
            "live_seconds_remaining": _legacy_seconds(starting_balance_ms),
        }
    )

    stop = asyncio.Event()
    start_ns = time.monotonic_ns()
    billed = False

    config = types.LiveConnectConfig(
        response_modalities=["AUDIO", "TEXT"],
        system_instruction=SYSTEM_INSTRUCTION,
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Puck")
            )
        ),
    )

    try:
        async with gemini().aio.live.connect(model=MODEL_NAME, config=config) as session:
            await websocket.send_json(
                {
                    "type": "connected",
                    "model": MODEL_NAME,
                }
            )
            with suppress(Exception):
                await session.send(
                    input=(
                        "Start live cricket detection now. Watch every incoming frame "
                        "and respond only with short coaching feedback when you detect "
                        "a mistake or a great shot."
                    ),
                    end_of_turn=True,
                )
            tasks = [
                asyncio.create_task(
                    _billing_guard(websocket, stop, start_ns, starting_balance_ms)
                ),
                asyncio.create_task(_from_flutter(websocket, session, stop)),
                asyncio.create_task(_from_gemini(websocket, session, stop)),
            ]
            done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            stop.set()
            for task in pending:
                task.cancel()
            for task in done:
                with suppress(WebSocketDisconnect):
                    task.result()
            elapsed_ms = min(
                starting_balance_ms,
                (time.monotonic_ns() - start_ns) // 1_000_000,
            )
            await _charge_elapsed_ms(user_id, elapsed_ms)
            billed = True
    except WebSocketDisconnect:
        stop.set()
    finally:
        stop.set()
        if not billed:
            elapsed_ms = min(
                starting_balance_ms,
                (time.monotonic_ns() - start_ns) // 1_000_000,
            )
            with suppress(Exception):
                await _charge_elapsed_ms(user_id, elapsed_ms)
