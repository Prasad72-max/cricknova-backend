import 'package:flutter/material.dart';

class PitchResultScreen extends StatelessWidget {
  final List<Map<String, double>> trajectory;
  final String speed;
  final String swing;
  final String spin;

  const PitchResultScreen({
    super.key,
    required this.trajectory,
    required this.speed,
    required this.swing,
    required this.spin,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Ball Tracking"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // 🏏 PITCH IMAGE
          Positioned.fill(
            child: Image.asset(
              "assets/pitch/pitch_360.jpg",
              fit: BoxFit.cover,
            ),
          ),

          // 🔵 BALL PATH
          Positioned.fill(
            child: CustomPaint(
              painter: BallPathPainter(trajectory),
            ),
          ),

          // 📊 LEFT SIDE STATS (LIKE FULLTRACK)
          Positioned(
            left: 16,
            top: 80,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statText("Speed", speed),
                  const SizedBox(height: 12),
                  _statText("Swing", swing.toUpperCase()),
                  const SizedBox(height: 12),
                  _statText("Spin", spin.toUpperCase()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statText(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// 🎯 BALL PATH PAINTER
class BallPathPainter extends CustomPainter {
  final List<Map<String, double>> points;

  BallPathPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    for (int i = 0; i < points.length; i++) {
      final x = points[i]['x']! * size.width;
      final y = points[i]['y']! * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}