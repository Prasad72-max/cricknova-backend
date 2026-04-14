import numpy as np

class ContactDetector:

    def detect_contact(self, smoothed_positions, min_frames=6):
        """
        Detects WHEN the bat impacts the ball using adaptive deceleration.
        Returns frame index of contact or None if evidence is insufficient.
        """

        if len(smoothed_positions) < min_frames:
            return None  # insufficient evidence

        velocities = []

        # Calculate per-frame ball speed
        for i in range(1, len(smoothed_positions)):
            p1 = np.array(smoothed_positions[i - 1])
            p2 = np.array(smoothed_positions[i])
            velocities.append(np.linalg.norm(p2 - p1))

        velocities = np.array(velocities)

        # Ignore near-zero noise
        valid = velocities[velocities > 1e-3]
        if len(valid) < 4:
            return None

        # Adaptive slowdown threshold based on median behaviour
        median_speed = np.median(valid)
        slowdown_indices = []

        for i in range(1, len(velocities)):
            if velocities[i - 1] > 0:
                ratio = velocities[i] / velocities[i - 1]
                if ratio < 0.6 and velocities[i - 1] > 0.5 * median_speed:
                    slowdown_indices.append(i)

        # Contact only if slowdown is sharp AND isolated
        if slowdown_indices:
            return slowdown_indices[0]

        return None