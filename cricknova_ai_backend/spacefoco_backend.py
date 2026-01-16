# Root entrypoint wrapper
# This file exists ONLY to support:
# uvicorn spacefoco_backend:app

from cricknova_ai_backend.spacefoco_backend import app

__all__ = ["app"]