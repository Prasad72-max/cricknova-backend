from fastapi import FastAPI

# Main FastAPI application
app = FastAPI(title="CrickNova AI Backend")

# Health check (Render & uptime)
@app.get("/")
def root():
    return {"status": "ok", "service": "CrickNova AI Backend"}