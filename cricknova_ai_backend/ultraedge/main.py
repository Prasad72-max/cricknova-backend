from .engine import UltraEdgeEngine

def run_ultraedge(audio_path):
    engine = UltraEdgeEngine(threshold=0.2)
    return engine.analyze(audio_path)