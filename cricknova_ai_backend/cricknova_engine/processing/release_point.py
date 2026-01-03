# FILE: cricknova_engine/processing/release_point.py

class ReleasePointEngine:

    def get_release_point(self, positions):
        if not positions:
            return None

        cx, cy = positions[0]
        return {"x": float(cx), "y": float(cy)}

    def normalize(self, release, img_width=720, img_height=1280):
        if not release:
            return None

        return {
            "nx": round(release["x"] / img_width, 4),
            "ny": round(release["y"] / img_height, 4),
        }

    def get_release_map(self, positions):
        raw = self.get_release_point(positions)
        return self.normalize(raw)