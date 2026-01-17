import numpy as np

class ContactDetector:

    def detect_contact(self, smoothed_positions, threshold=0.45):
        """
        Detects WHEN the bat impacts the ball.
        smoothed_positions = list of (x,y) ball positions
        threshold = how sharp the slowdown must be to count as contact
        """

        if len(smoothed_positions) < 5:
            return None   # not enough frames

        velocities = []

        # Calculate ball speed between frames
        for i in range(1, len(smoothed_positions)):
            p1 = np.array(smoothed_positions[i - 1])
            p2 = np.array(smoothed_positions[i])
            dist = np.linalg.norm(p2 - p1)
            velocities.append(dist)

        # Find sudden slowdown (ball loses speed at bat contact)
        for i in range(2, len(velocities)):
            prev_speed = velocities[i - 1]
            curr_speed = velocities[i]

            # ball suddenly decelerates
            if prev_speed > 0 and (curr_speed / prev_speed) < threshold:
                return i  # this frame is contact

        return None