import asyncio
import websockets
import json
import ssl

async def test():
    uri = "wss://cricknova-backend.onrender.com/ws/live-nets/testuser123"
    print(f"Connecting to {uri}...")
    
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE

    try:
        async with websockets.connect(uri, ssl=ssl_context) as websocket:
            print("Connected! Sending client_config...")
            config = {
                "type": "client_config",
                "name": "PlayerTest",
                "language": "Marathi",
                "discipline": "Batting"
            }
            await websocket.send(json.dumps(config))
            print("Config sent, listening for messages...")
            while True:
                msg = await websocket.recv()
                print(f"Received: {msg}")
    except Exception as e:
        print(f"Connection closed/failed with error: {e}")

if __name__ == "__main__":
    asyncio.run(test())
