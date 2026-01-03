import 'package:flutter/material.dart';
import 'package:panorama/panorama.dart';

class Pitch360View extends StatelessWidget {
  final Map<String, dynamic> data;

  const Pitch360View({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("360° Pitch View"),
      ),
      body: Stack(
        children: [
          Panorama(
            animSpeed: 0.0,
            sensorControl: SensorControl.Orientation,
            child: Image.asset(
              "assets/pitch_360.jpg",
              fit: BoxFit.cover,
            ),
          ),

          // LEFT PANEL (speed, swing, spin)
          Positioned(
            left: 12,
            top: 80,
            child: _infoBox(data),
          ),

          // BALL PATH PLACEHOLDER (we connect real data next)
          Positioned.fill(
            child: CustomPaint(
              painter: BallPathPainter(
                data["trajectory"] ?? [],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row("Speed", "${data["speed_kmph"] ?? "--"} km/h"),
          _row("Swing", data["swing"] ?? "--"),
          _row("Spin", data["spin"] ?? "--"),
        ],
      ),
    );
  }

  Widget _row(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        "$title: $value",
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}

class BallPathPainter extends CustomPainter {
  final List points;

  BallPathPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final glowPaint = Paint()
      ..color = Colors.red.withOpacity(0.4)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final paint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    Offset toOffset(int i) {
      final x = (points[i]["x"] ?? 0.5) * size.width;
      final y = (points[i]["y"] ?? 0.5) * size.height;
      return Offset(x, y);
    }

    path.moveTo(toOffset(0).dx, toOffset(0).dy);

    for (int i = 1; i < points.length - 1; i++) {
      final p1 = toOffset(i);
      final p2 = toOffset(i + 1);
      final mid = Offset(
        (p1.dx + p2.dx) / 2,
        (p1.dy + p2.dy) / 2,
      );
      path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}