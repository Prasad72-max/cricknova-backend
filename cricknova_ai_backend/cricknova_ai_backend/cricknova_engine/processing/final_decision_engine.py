# ------------------------------------------------------------
# FINAL AI DECISION ENGINE
# Shot Result + Edge + Wicket Auto Detection
# ------------------------------------------------------------

import numpy as np

class FinalDecisionEngine:
    def __init__(self):
        # thresholds
        self.min_bat_speed = 1.2
        self.min_deflection_for_shot = 10
        self.min_lift_for_air = 12

    def decide(self, fusion_result, trajectory, bat_path, ball_path, keeper_line_y):
        """
        fusion_result: output from FusionEngine.fuse()
        trajectory: { angle_before, angle_after, dx, dy, angle_deg, lift }
        bat_path: list of (x,y)
        ball_path: list of (x,y)
        keeper_line_y: y-value where wicketkeeper catches ball
        """

        # ------------------------------------------------------------
        # 1) Check for EDGE from fusion engine
        # ------------------------------------------------------------
        if fusion_result["edge"]:
            edge_type = fusion_result["type"]
            conf = fusion_result["confidence"]

            # check if ball went straight to wicketkeeper height zone
            ball_end_y = ball_path[-1][1]

            if abs(ball_end_y - keeper_line_y) < 25:
                return {
                    "out": True,
                    "how": "caught_behind",
                    "edge": True,
                    "edge_type": edge_type,
                    "confidence": conf,
                    "runs": 0,
                    "shot": "none"
                }

            # edge but not out → result depends on deflection
            return {
                "out": False,
                "how": "edge_only",
                "edge": True,
                "edge_type": edge_type,
                "confidence": conf,
                "runs": self._auto_runs_from_edge(trajectory),
                "shot": "edge_deflection"
            }

        # ------------------------------------------------------------
        # 1.5) NO EDGE → Check direct wicket (bowled / LBW via stumps)
        # ------------------------------------------------------------
        stump_hit = fusion_result.get("stump_hit", False)

        if stump_hit:
            return {
                "out": True,
                "how": "bowled",
                "edge": False,
                "runs": 0,
                "shot": "none"
            }

        # ------------------------------------------------------------
        # 2) No edge → Did batsman hit?
        # Check bat movement + ball deviation
        # ------------------------------------------------------------
        bat_speed = self._bat_speed(bat_path)
        deviation = abs(trajectory.get("angle_after", 0) - trajectory.get("angle_before", 0))
        lift = trajectory.get("lift", 0)

        if bat_speed < self.min_bat_speed:
            # bat didnt swing enough = no shot
            return {
                "out": False,
                "how": "no_shot",
                "edge": False,
                "runs": 0,
                "shot": "dot"
            }

        # ------------------------------------------------------------
        # 3) Shot classification (no edge)
        # ------------------------------------------------------------

        # heavy hit → boundary
        if lift > self.min_lift_for_air and deviation > 25:
            return {
                "out": False,
                "how": "shot",
                "edge": False,
                "runs": 6,
                "shot": "six"
            }

        if deviation > 18:
            return {
                "out": False,
                "how": "shot",
                "edge": False,
                "runs": 4,
                "shot": "four"
            }

        # medium strike → runs 1–3 based on ball slowdown
        slowdown = self._slowdown(ball_path)
        run_value = self._runs_from_slowdown(slowdown)

        return {
            "out": False,
            "how": "shot",
            "edge": False,
            "runs": run_value,
            "shot": f"run_{run_value}"
        }


    # ------------------------------------------------------
    # HELPERS
    # ------------------------------------------------------

    def _bat_speed(self, bat_path):
        if len(bat_path) < 3:
            return 0.0
        p1 = np.array(bat_path[-1])
        p2 = np.array(bat_path[-3])
        return float(np.linalg.norm(p1 - p2))

    def _slowdown(self, ball_path):
        if len(ball_path) < 4:
            return 1.0
        early = np.linalg.norm(np.array(ball_path[1]) - np.array(ball_path[0]))
        late  = np.linalg.norm(np.array(ball_path[-1]) - np.array(ball_path[-2]))
        return late / (early + 0.0001)

    def _runs_from_slowdown(self, s):
        # ball slowed down a lot = only 1 run
        if s < 0.35:
            return 1
        if s < 0.50:
            return 2
        if s < 0.70:
            return 3
        return 0  # dot

    def _auto_runs_from_edge(self, traj):
        dev = abs(traj["angle_after"] - traj["angle_before"])
        if dev > 25:
            return 4
        if dev > 15:
            return 2
        return 1