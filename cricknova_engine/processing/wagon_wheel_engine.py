import math


class WagonWheelEngine:

    def __init__(self):
        self.shots = []              # full list of shots in innings
        self.fielder_map = {}        # optional: {"cover": 2 fielders}
        self.auto_zones = [          # angle zones for classification
            ("fine_leg", -70, -40),
            ("square_leg", -40, -10),
            ("midwicket", -10, 20),
            ("long_on", 20, 50),
            ("straight", 50, 70),
            ("long_off", 70, 100),
            ("cover", 100, 140),
            ("point", 140, 170),
            ("third_man", 170, 200),
        ]

    # ---------------------------------------------------------
    # CLASSIFY ANGLE → SHOT ZONE
    # ---------------------------------------------------------
    def _zone_from_angle(self, angle):
        for zone, a_min, a_max in self.auto_zones:
            if a_min <= angle <= a_max:
                return zone
        return "unknown"

    # ---------------------------------------------------------
    # ADD SHOT
    # ---------------------------------------------------------
    def add_shot(self, launch_angle, exit_angle, distance):
        zone = self._zone_from_angle(exit_angle)
        runs = self._predict_runs(distance, zone)

        shot = {
            "launch_angle": launch_angle,
            "exit_angle": exit_angle,
            "distance": distance,
            "zone": zone,
            "predicted_runs": runs
        }

        self.shots.append(shot)
        return shot

    # ---------------------------------------------------------
    # RUN PREDICTION BASED ON DISTANCE
    # ---------------------------------------------------------
    def _predict_runs(self, distance, zone):
        if distance >= 65:
            return 6
        if distance >= 45:
            return 4
        if distance >= 25:
            return 2
        if distance >= 10:
            return 1
        return 0

    # ---------------------------------------------------------
    # FIELDING AI (OPTIONAL)
    # ---------------------------------------------------------
    def add_fielder(self, zone, count=1):
        self.fielder_map[zone] = self.fielder_map.get(zone, 0) + count

    def danger_level(self, zone):
        count = self.fielder_map.get(zone, 0)
        if count >= 3: return "High"
        if count == 2: return "Medium"
        if count == 1: return "Low"
        return "Free Hit Zone"